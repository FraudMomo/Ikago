import Foundation
import WebKit

/// Maps a Space's profile ID to its WebKit storage. "Default" is the shared store; an
/// isolated Space (its UUID string) gets its own persistent `WKWebsiteDataStore`, so
/// cookies, logins and site data never cross Spaces. Every store is an identifier store, which keeps
/// all its files in one folder inside protected storage (`ProtectedStorage`); WebKit's built-in
/// `.default()` store is never used, because its cookie file can't be moved there.
@MainActor
enum WebProfiles {
    private static var stores: [String: WKWebsiteDataStore] = [:]
    /// Settings ▸ Developer tools; new pages read it, live pages are updated by the window.
    static var developerTools = true

    static func dataStore(for profileID: String) -> WKWebsiteDataStore {
        if let store = stores[profileID] { return store }
        let store: WKWebsiteDataStore
        if isTestMode, !isPrivate(profileID), let identifier = persistenceTestIdentifier {
            store = WKWebsiteDataStore(forIdentifier: identifier)
        } else if isTestMode || isPrivate(profileID) || CEFSessions.overrideRoot != nil {
            // CEFSessions.overrideRoot: a Chromium check run, whose WebKit pages must never reach real stores either.
            store = .nonPersistent()  // private windows: in memory only, gone when the window closes  // unattended tests never touch real cookies
        } else if profileID != "Default", let uuid = UUID(uuidString: profileID) {
            store = WKWebsiteDataStore(forIdentifier: uuid)
        } else {
            store = WKWebsiteDataStore(forIdentifier: ProtectedStorage.defaultStoreID)
        }
        stores[profileID] = store
        return store
    }

    /// Configuration for a new tab in `profileID`. Popups instead reuse the configuration
    /// WebKit hands to `createWebViewWith` (same store, opener kept).
    static func configuration(for profileID: String) -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = dataStore(for: profileID)
        if !isPrivate(profileID) { config.webExtensionController = ExtensionManager.shared.controller(for: profileID) }
        MediaMonitor.shared.install(in: config.userContentController)
        LinkHoverMonitor.shared.install(in: config.userContentController)
        WebStoreBridge.shared.install(in: config.userContentController)
        PasswordAutoFill.shared.install(in: config.userContentController)
        config.preferences.isElementFullscreenEnabled = true
        config.preferences.isFraudulentWebsiteWarningEnabled = BrowserSecurity.shared.preferences.fraudulentWebsiteWarning ?? true
        // WebKit's own popup blocker: window.open() needs a user gesture.
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.defaultWebpagePreferences.preferredContentMode = .desktop
        config.allowsAirPlayForMediaPlayback = true
        // Sites sniff for "Safari"; WKWebView's default user agent omits it.
        config.applicationNameForUserAgent = "Version/\(safariMajorVersion).0 Safari/605.1.15"
        return config
    }

    /// Safari's major version tracks macOS since macOS 26 (Safari 26).
    private static var safariMajorVersion: Int {
        let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        return major >= 26 ? major : 18
    }

    static func isPrivate(_ profileID: String) -> Bool { profileID.hasPrefix("Private-") }
    /// Whether a page's store belongs to a private window. Popups share their opener's store.
    static func isPrivateStore(_ store: WKWebsiteDataStore) -> Bool {
        stores.contains { isPrivate($0.key) && $0.value === store }
    }

    /// Writes every persistent store's cookies to disk before quitting. WebKit's networking
    /// process saves cookies lazily and exits with the app, so a write in flight at quit
    /// (a login, a rotated "remember this device" token) was lost, leaving an older file.
    /// Calls `completion` once, after every store answered or `timeout`; at once without the SPI.
    /// Callback-based (no Swift task) so it also finishes inside `.terminateLater`'s modal loop.
    static func flushCookies(timeout: TimeInterval = 2, evenOnChromium: Bool = false, completion: @escaping @MainActor () -> Void) {
        // On Chromium this would usually only start WebKit's network process to flush nothing, delaying
        // the quit. The exception is a switch to WebKit, which has just copied cookies into these stores.
        guard BrowserRuntime.runs(.webkit) || evenOnChromium else { return completion() }
        // SPI: -[WKHTTPCookieStore _flushCookiesToDiskWithCompletionHandler:]; no public flush exists.
        let selector = NSSelectorFromString("_flushCookiesToDiskWithCompletionHandler:")
        let persistent = stores.values.filter(\.isPersistent)
        let cookieStores = persistent.map(\.httpCookieStore).filter { $0.responds(to: selector) }
        guard !cookieStores.isEmpty else { return completion() }
        typealias Flush = @convention(c) (AnyObject, Selector, @escaping @convention(block) () -> Void) -> Void
        let pending = FlushCountdown(cookieStores.count, completion)
        for cookieStore in cookieStores {
            let flush = unsafeBitCast(cookieStore.method(for: selector), to: Flush.self)
            flush(cookieStore, selector) { MainActor.assumeIsolated { pending.tick() } }
        }
        let timer = Timer(timeInterval: timeout, repeats: false) { _ in MainActor.assumeIsolated { pending.finish() } }
        RunLoop.main.add(timer, forMode: .common)
    }

    static func clearWebKitWebsiteData(_ profileID: String) async {
        await dataStore(for: profileID).removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
    }
    /// Drops a private window's store so its cookies and storage are released with it.
    static func forget(_ profileID: String) {
        stores[profileID] = nil
        if BrowserRuntime.runs(.chromium) { CEFSessions.forget(profileID) }
    }

    /// Explicit restart fixture only: a freshly generated, disposable UUID, never a user profile.
    static var persistenceTestIdentifier: UUID? {
        #if DEBUG
        guard isTestMode else { return nil }
        return DebugEnvironment.value("IKAGO_TEST_STORAGE_UUID").flatMap(UUID.init(uuidString:))
        #else
        return nil
        #endif
    }

    static var isTestMode: Bool {
        #if DEBUG
        DebugEnvironment.value("IKAGO_TEST_MODE") != nil
        #else
        false
        #endif
    }
}

/// Calls its completion once, when every flush has answered or on timeout.
@MainActor
private final class FlushCountdown {
    private var remaining: Int
    private var completion: (@MainActor () -> Void)?
    init(_ count: Int, _ completion: @escaping @MainActor () -> Void) { remaining = count; self.completion = completion }
    func tick() { remaining -= 1; if remaining <= 0 { finish() } }
    func finish() { completion?(); completion = nil }
}
