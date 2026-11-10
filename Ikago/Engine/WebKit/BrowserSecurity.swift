import Foundation
import WebKit

/// Public WebKit protections, shared by every Space while keeping their storage separate.
@MainActor
@Observable
final class BrowserSecurity {
    static let shared = BrowserSecurity()
    var preferences = BrowserPreferences()
    private(set) var blockingIssue: String?
    private var trackerRules: WKContentRuleList?
    private var cookieRules: WKContentRuleList?
    private let pages = NSHashTable<WebKitTab>.weakObjects()

    // Deliberately scoped to known tracking hosts; no blanket blocking of third-party scripts.
    static let trackerDomains = ["google-analytics.com", "doubleclick.net", "googlesyndication.com",
        "googleadservices.com", "scorecardresearch.com", "quantserve.com", "quantcount.com",
        "adsrvr.org", "adnxs.com", "criteo.com", "criteo.net", "outbrain.com", "taboola.com",
        "demdex.net", "omtrdc.net", "everesttech.net", "hotjar.com", "hotjar.io", "clarity.ms",
        "mouseflow.com", "fullstory.com", "mixpanel.com", "segment.io", "segment.com",
        "amplitude.com", "pubmatic.com", "rubiconproject.com", "casalemedia.com", "mathtag.com"]

    static func trackerJSON(domains: [String] = trackerDomains) throws -> String {
        let rules: [[String: Any]] = domains.map { domain in
            ["trigger": ["url-filter": "^https?://([a-z0-9-]+\\.)*" + NSRegularExpression.escapedPattern(for: domain) + "[:/]", "load-type": ["third-party"]], "action": ["type": "block"]]
        }
        return String(decoding: try JSONSerialization.data(withJSONObject: rules), as: UTF8.self)
    }
    static let cookieJSON = #"[{"trigger":{"url-filter":".*","load-type":["third-party"]},"action":{"type":"block-cookies"}}]"#

    func prepare() async {
        do {
            let store: WKContentRuleListStore
            if WebProfiles.isTestMode {
                let directory = SessionStore.testDirectory.appending(path: "ContentRules")
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                store = WKContentRuleListStore(url: directory)
            } else { store = .default() }
            trackerRules = try await store.compileContentRuleList(forIdentifier: "IkagoCommonTrackers-v1", encodedContentRuleList: Self.trackerJSON())
            cookieRules = try await store.compileContentRuleList(forIdentifier: "IkagoThirdPartyCookies-v1", encodedContentRuleList: Self.cookieJSON)
            blockingIssue = nil
        } catch { blockingIssue = "Content protection could not start: \(error.localizedDescription)" }
    }
    func register(_ page: WebKitTab) { pages.add(page); configure(page) }
    func apply(_ preferences: BrowserPreferences) {
        if BrowserRuntime.runs(.chromium) { CEFProtection.apply(preferences) }
        guard self.preferences != preferences else { return }
        let reconfigure = SecuritySettings(self.preferences) != SecuritySettings(preferences)
        self.preferences = preferences
        // Only protection changes touch the pages' rule lists; other preferences are just remembered.
        if reconfigure { for page in pages.allObjects { configure(page) } }
    }
    private func configure(_ page: WebKitTab) {
        page.webView.configuration.preferences.isFraudulentWebsiteWarningEnabled = preferences.fraudulentWebsiteWarning ?? true
        let controller = page.webView.configuration.userContentController
        if let trackerRules {
            controller.remove(trackerRules)
            if preferences.blockTrackers ?? true { controller.add(trackerRules) }
        }
        if let cookieRules {
            controller.remove(cookieRules)
            if preferences.blockThirdPartyCookies ?? true { controller.add(cookieRules) }
        }
    }
    var httpsPolicy: WKWebpagePreferences.UpgradeToHTTPSPolicy {
        if preferences.forceHTTPS == true { return .errorOnFailure }
        return preferences.warnInsecureHTTP ?? true ? .userMediatedFallbackToHTTP : .automaticFallbackToHTTP
    }
    func httpsPolicy(for url: URL) -> WKWebpagePreferences.UpgradeToHTTPSPolicy {
        // HTTPS upgrading is only meaningful for network pages. Applying it to file:
        // navigation can make WebKit replace the local document with about:blank.
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return .keepAsRequested }
        let host = url.host?.lowercased() ?? ""
        // Loopback is never auto-upgraded (dev servers rarely have certificates); in HTTPS-only
        // mode it and the user's exceptions keep HTTP only when allowed in Settings.
        if preferences.forceHTTPS == true { return preferences.allowsHTTP(host: host) ? .keepAsRequested : httpsPolicy }
        return BrowserPreferences.isLoopback(host) ? .keepAsRequested : httpsPolicy
    }
    /// Whether HTTPS-only mode must upgrade or block this HTTP address.
    func requiresHTTPS(_ url: URL) -> Bool {
        preferences.forceHTTPS == true && url.scheme?.lowercased() == "http" && !preferences.allowsHTTP(host: url.host ?? "")
    }

    /// Strict mode never sends a top-level HTTP request, except to allowed exceptions.
    static func secureURL(_ url: URL) -> URL? {
        guard url.scheme?.lowercased() == "http", var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        parts.scheme = "https"
        if parts.port == 80 { parts.port = nil }
        return parts.url
    }
}

/// The preferences that decide content protection on both engines, so other preference changes
/// don't recompile or re-add rule lists.
struct SecuritySettings: Equatable {
    var blockTrackers, blockThirdPartyCookies, fraudulentWebsiteWarning, forceHTTPS, httpsAllowLocal: Bool?
    var httpsExceptions: String?

    init(_ preferences: BrowserPreferences) {
        blockTrackers = preferences.blockTrackers
        blockThirdPartyCookies = preferences.blockThirdPartyCookies
        fraudulentWebsiteWarning = preferences.fraudulentWebsiteWarning
        forceHTTPS = preferences.forceHTTPS
        httpsAllowLocal = preferences.httpsAllowLocal
        httpsExceptions = preferences.httpsExceptions
    }
}
