import Foundation
import IKCEFBridge
import WebKit

/// Keeps people signed in when they switch engines. Only a Chromium run can reach both cookie stores,
/// so all copying happens there: WebKit → Chromium on the launch after a switch, Chromium → WebKit on
/// the quit before one. Nothing is written outside each engine's own store, and values are never logged.
///
/// After a clean switch the engine used last is authoritative, so a logout carries over too. With no
/// record of a clean switch (the first sync, or Chromium quit without exporting) the copy only adds and
/// overwrites, because deleting could remove logins that were never synced.
@MainActor
enum EngineCookieSync {
    struct Summary: Equatable { var copied = 0, removed = 0, rejected = 0 }

    private static let ownersKey = "EngineCookieOwners"
    private static let pendingClearKey = "CEFProfilesToClear"
    private static let quitBudget: TimeInterval = 15

    /// The checks use disposable profiles and must never reach the user's WebKit store.
    static var usesRealStores: Bool { CEFSessions.overrideRoot == nil && !WebProfiles.isTestMode }

    private static var owners: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: ownersKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: ownersKey) }
    }

    // MARK: Launch and quit

    /// A WebKit launch can't export Chromium's cookies, so a leftover Chromium claim means the last
    /// export didn't finish. Forget it: the next copy then merges rather than deletes.
    static func noteWebKitLaunch() {
        guard usesRealStores else { return }
        owners = owners.filter { $0.value != BrowserEngine.chromium.rawValue }
    }

    /// Before the first tab of a launch with Chromium as the default engine. Sites a rule keeps on Chromium are
    /// left alone: Chromium already holds their newest logins.
    static func prepareChromium(profiles: Set<String>, preferences: BrowserPreferences) async {
        await applyPendingClears()
        guard usesRealStores else { return }
        for profile in profiles.sorted() where owners[profile] != BrowserEngine.chromium.rawValue {
            do {
                try CEFSessions.prepare(profile)
                let store = WebProfiles.dataStore(for: profile).httpCookieStore
                let mirror = owners[profile] == BrowserEngine.webkit.rawValue
                _ = try await copyToChromium(from: store, profile: profile, mirror: mirror,
                                             including: { !ruled(domain: $0, to: .chromium, preferences: preferences) })
                owners[profile] = BrowserEngine.chromium.rawValue
            } catch {
                NSLog("Ikago: couldn't copy WebKit cookies for a Space: %@", error.localizedDescription)
            }
        }
    }

    /// On a Chromium quit, only when WebKit is the engine for the next launch.
    static func exportIfSwitching(state: BrowserState?, completion: @escaping @MainActor () -> Void) {
        guard usesRealStores, BrowserRuntime.engine == .chromium, let state,
              state.browserPreferences.preferredEngine == .webkit else { return completion() }
        let profiles = Set(state.spaces.map(\.profileID))
        let deadline = Date().addingTimeInterval(quitBudget)
        Task { @MainActor in
            for profile in profiles.sorted() {
                do {
                    try CEFSessions.prepare(profile)
                    let store = WebProfiles.dataStore(for: profile).httpCookieStore
                    // Only a run that started with this Space's WebKit cookies may delete from WebKit.
                    let mirror = owners[profile] == BrowserEngine.chromium.rawValue
                    _ = try await copyToWebKit(profile: profile, store: store, mirror: mirror, deadline: deadline,
                                               including: { !ruled(domain: $0, to: .webkit, preferences: state.browserPreferences) })
                    owners[profile] = BrowserEngine.webkit.rawValue
                } catch {
                    owners[profile] = nil
                    NSLog("Ikago: couldn't copy Chromium cookies for a Space: %@", error.localizedDescription)
                }
            }
            WebProfiles.flushCookies(evenOnChromium: true, completion: completion)
        }
    }

    // MARK: Clearing

    /// Clearing website data applies to both engines, or a cleared login would return after a switch (or on a site
    /// that uses the other engine). Chromium is cleared now when it runs, otherwise at its next launch.
    static func clearBothEngines(profile: String, knownURLs: [String]) async throws {
        // Chromium checks use disposable Chromium profiles and must never reach the real WebKit store.
        if usesRealStores || !BrowserRuntime.runs(.chromium) { await WebProfiles.clearWebKitWebsiteData(profile) }
        guard BrowserRuntime.runs(.chromium) else { return retryChromiumClear(profile: profile) }
        do { try await ChromiumWebsiteData.clear(profile: profile, knownURLs: knownURLs) }
        catch { retryChromiumClear(profile: profile); throw error }
    }

    /// A Chromium clear failed: try again at the next launch, before any tab opens.
    static func retryChromiumClear(profile: String) {
        guard usesRealStores else { return }
        let pending = Set(UserDefaults.standard.stringArray(forKey: pendingClearKey) ?? []).union([profile])
        UserDefaults.standard.set(pending.sorted(), forKey: pendingClearKey)
    }

    private static func applyPendingClears() async {
        guard usesRealStores else { return }
        for profile in UserDefaults.standard.stringArray(forKey: pendingClearKey) ?? [] {
            do { try await ChromiumWebsiteData.clear(profile: profile) }
            catch { NSLog("Ikago: couldn't clear Chromium data for a Space: %@", error.localizedDescription); continue }
            let remaining = (UserDefaults.standard.stringArray(forKey: pendingClearKey) ?? []).filter { $0 != profile }
            UserDefaults.standard.set(remaining, forKey: pendingClearKey)
        }
    }

    // MARK: Copying

    /// `including`: which cookie domains to copy (and, mirroring, delete); every one by default.
    static func copyToChromium(from store: WKHTTPCookieStore, profile: String, mirror: Bool,
                               including: (String) -> Bool = { _ in true }) async throws -> Summary {
        let source = await store.allCookies().filter { including($0.domain) }
        var summary = Summary()
        if mirror {
            let keep = Set(source.map(key))
            for item in try await chromiumCookies(profile) where !keep.contains(key(item)) && including(item["domain"] as? String ?? "") {
                if await deleteFromChromium(item, profile: profile) { summary.removed += 1 }
            }
        }
        for cookie in source {
            // WebKit stores SameSite=None as no policy, so a secure cookie keeps working in third-party contexts.
            let sameSite = cookie.sameSitePolicy == .sameSiteLax ? 1 : cookie.sameSitePolicy == .sameSiteStrict ? 2 : cookie.isSecure ? 0 : -1
            let accepted: Bool = await withCheckedContinuation { continuation in
                IKCEFContexts.setCookie(cookie, sameSite: sameSite, profile: profile) { error in continuation.resume(returning: error == nil) }
            }
            if accepted { summary.copied += 1 } else { summary.rejected += 1 }
        }
        return summary
    }

    static func copyToWebKit(profile: String, store: WKHTTPCookieStore, mirror: Bool, deadline: Date = .distantFuture,
                             including: (String) -> Bool = { _ in true }) async throws -> Summary {
        let source = try await chromiumCookies(profile).filter { including($0["domain"] as? String ?? "") }
        var summary = Summary()
        if mirror {
            let keep = Set(source.map(key))
            for cookie in await store.allCookies() where !keep.contains(key(cookie)) && including(cookie.domain) {
                guard Date() < deadline else { throw CEFError.script("Ran out of time copying cookies.") }
                await store.deleteCookie(cookie)
                summary.removed += 1
            }
        }
        for item in source {
            guard Date() < deadline else { throw CEFError.script("Ran out of time copying cookies.") }
            guard let cookie = webKitCookie(item) else { summary.rejected += 1; continue }
            await store.setCookie(cookie)
            summary.copied += 1
        }
        return summary
    }

    static func chromiumCookies(_ profile: String) async throws -> [[String: Any]] {
        let items: [[String: Any]]? = await withCheckedContinuation { continuation in
            IKCEFContexts.cookies(forProfile: profile) { nonisolated(unsafe) let result = $0; continuation.resume(returning: result) }
        }
        guard let items else { throw CEFError.script("Chromium refused to read this Space's cookies.") }
        return items
    }

    private static func deleteFromChromium(_ item: [String: Any], profile: String) async -> Bool {
        guard let name = item["name"] as? String, let url = url(item) else { return false }
        return await withCheckedContinuation { continuation in
            IKCEFContexts.deleteCookieNamed(name, url: url, profile: profile) { continuation.resume(returning: $0) }
        }
    }

    private static func url(_ item: [String: Any]) -> String? {
        guard let domain = item["domain"] as? String else { return nil }
        var components = URLComponents()
        components.scheme = item["secure"] as? Bool == true ? "https" : "http"
        components.host = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
        components.path = item["path"] as? String ?? "/"
        return components.url?.absoluteString
    }

    private static func webKitCookie(_ item: [String: Any]) -> HTTPCookie? {
        guard let name = item["name"] as? String, let value = item["value"] as? String,
              let domain = item["domain"] as? String, let path = item["path"] as? String else { return nil }
        var properties: [HTTPCookiePropertyKey: Any] = [.name: name, .value: value, .domain: domain, .path: path]
        if item["secure"] as? Bool == true { properties[.secure] = "TRUE" }
        if item["httpOnly"] as? Bool == true { properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
        if let expires = item["expires"] as? Double { properties[.expires] = Date(timeIntervalSince1970: expires) }
        else { properties[.discard] = "TRUE" }
        switch item["sameSite"] as? Int {
        case 1: properties[.sameSitePolicy] = HTTPCookieStringPolicy.sameSiteLax.rawValue
        case 2: properties[.sameSitePolicy] = HTTPCookieStringPolicy.sameSiteStrict.rawValue
        default: break
        }
        return HTTPCookie(properties: properties)
    }

    private static func key(_ cookie: HTTPCookie) -> String { "\(cookie.name)|\(cookie.domain)|\(cookie.path)" }
    private static func key(_ item: [String: Any]) -> String {
        "\(item["name"] as? String ?? "")|\(item["domain"] as? String ?? "")|\(item["path"] as? String ?? "")"
    }
}
