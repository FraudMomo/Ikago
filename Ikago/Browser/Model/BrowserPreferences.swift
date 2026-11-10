import Foundation

struct BrowserPreferences: Codable, Equatable {
    var browserEngine: String? = nil
    /// X's H.264 video on Chromium is translated to AV1 so X's own player plays it (`MediaTranslation`). Unset: on.
    var chromiumVideoTranslation: Bool? = nil
    /// Chromium tabs' sound played by Ikago, so the media island can draw its real wave (`IKCEFAudio`). Off unless chosen:
    /// it adds about 40 ms of audio delay.
    var chromiumLiveWave: Bool? = nil
    /// The person's own sites → engine raw value (`SiteEngines`). Hosts cover their subdomains.
    var siteEngines: [String: String]? = nil
    /// Ready-made lists (`SiteEngineList.id`) → engine raw value. A list without an entry follows the default engine.
    var siteEngineLists: [String: String]? = nil

    var showPinnedGrid: Bool? = nil
    var reuseBookmarkTabs: Bool? = nil
    var bookmarkMatchDomain: Bool? = nil
    var loadBackgroundTabs: Bool? = nil
    var translucentSidebar: Bool? = nil
    /// The shown sidebar is a rail of icons (`SidebarRail`) instead of the full list. Unset: full.
    var sidebarCompact: Bool? = nil
    /// Full screen uses the whole display, around the camera housing, instead of starting below it. Unset: off.
    var fullScreenUnderNotch: Bool? = nil
    /// On by default. Sessions from before that default get it once (`httpsDefaultApplied`), after which
    /// the setting is the person's own.
    var forceHTTPS: Bool? = true
    var httpsDefaultApplied: Bool? = true
    /// Sites allowed to download files, and whether to ask at all.
    var askBeforeDownloads: Bool? = nil
    var downloadSites: [String]? = nil
    /// Hosts the person chose to open despite a phishing warning.
    var siteSafetyExceptions: [String]? = nil
    var warnInsecureHTTP: Bool? = nil
    var blockTrackers: Bool? = nil
    var blockThirdPartyCookies: Bool? = nil
    var fraudulentWebsiteWarning: Bool? = nil
    /// Shows the key in sign-in fields that opens Apple's Passwords panel.
    var passwordAutoFill: Bool? = nil
    /// "ikago" fills from Ikago's own vault, "apple" from Apple Passwords (WebKit only). Unset: Ikago's
    /// vault once something was imported into it, otherwise Apple Passwords. Chromium always uses the vault.
    var passwordSource: String? = nil
    /// HTTPS-only mode still lets localhost/loopback use HTTP (development servers).
    var httpsAllowLocal: Bool? = nil
    /// Extra hosts that may use HTTP, comma- or space-separated (subdomains included).
    var httpsExceptions: String? = nil
    var clearDataOnQuit: Bool? = nil
    var hibernationEnabled = false
    var hibernationMinutes = 30
    var protectPinnedTabs = true
    var hibernationExceptions = ""
    var showSwitchToTabSuggestions: Bool? = nil
    var searchEngineAutocomplete: Bool? = nil
    var instantTabSwitching: Bool? = nil
    var tabHighlightStyle: String? = nil
    var groupLabelStyle: String? = nil
    var showGroupTabCounts: Bool? = nil
    var showTopBarEssentials: Bool? = nil
    var showTopBarPins: Bool? = nil
    var showBookmarksBar: Bool? = nil
    var sidebarBookmarksExpanded: Bool? = nil
    var topTabStyle: String? = nil
    var topBarShowPageColor: Bool? = nil
    var topBarAlwaysShowTabBar: Bool? = nil
    /// Top Bar toolbar (Separate) or single tab row (Compact) height, and the Separate tab bar's.
    var topToolbarHeight: Double? = nil
    var topTabBarHeight: Double? = nil
    var newTabPosition: String? = nil
    var linkTabPosition: String? = nil

    var validated: Self {
        var copy = self
        copy.hibernationMinutes = min(1440, max(1, hibernationMinutes))
        copy.hibernationExceptions = String(hibernationExceptions.prefix(4096))
        copy.httpsExceptions = httpsExceptions.map { String($0.prefix(4096)) }
        if httpsDefaultApplied != true { copy.forceHTTPS = true; copy.httpsDefaultApplied = true }
        copy.downloadSites = downloadSites.map { Array($0.prefix(2000)) }
        copy.siteSafetyExceptions = siteSafetyExceptions.map { Array($0.prefix(2000)) }
        return copy
    }

    /// Whether `host` may load over plain HTTP even in HTTPS-only mode.
    func allowsHTTP(host: String) -> Bool {
        let host = host.lowercased()
        if httpsAllowLocal ?? true, Self.isLoopback(host) { return true }
        return (httpsExceptions ?? "").split(whereSeparator: { $0 == "," || $0.isWhitespace }).contains { entry in
            var domain = String(entry).lowercased()
            if let parsed = URLComponents(string: domain.contains("://") ? domain : "http://" + domain)?.host { domain = parsed }
            domain = domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return !domain.isEmpty && (host == domain || host.hasSuffix("." + domain))
        }
    }

    static func isLoopback(_ host: String) -> Bool {
        let parts = host.split(separator: ".")
        return host == "localhost" || host.hasSuffix(".localhost") || host == "[::1]" || host == "::1"
            || (parts.count == 4 && host.hasPrefix("127.") && parts.allSatisfy { UInt8($0) != nil })
    }

    func protects(_ url: String) -> Bool {
        guard let host = URL(string: url)?.host?.lowercased() else { return true }
        return hibernationExceptions.split(whereSeparator: { $0 == "," || $0.isWhitespace }).contains { entry in
            let domain = String(entry).lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return !domain.isEmpty && (host == domain || host.hasSuffix("." + domain))
        }
    }
}

struct Bookmark: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var url: String
    var title: String
    var favicon: String? = nil
    var folderID: String? = nil
}

extension BrowserState {
    func addBookmark(_ tab: TabItem) {
        guard AddressResolver.isWebURL(tab.url), bookmarks.count < 5000,
              !bookmarks.contains(where: { $0.url == tab.url }) else { return }
        bookmarks.append(Bookmark(url: tab.url, title: String(tab.displayTitle.prefix(512)), favicon: tab.faviconURL?.absoluteString))
        scheduleSave()
    }
}
