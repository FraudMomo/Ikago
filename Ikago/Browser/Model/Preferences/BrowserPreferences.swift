import Foundation

struct BrowserPreferences: Codable, Equatable {
    var pageIntelligence: Bool? = nil
    var assistantToolbarInitialized: Bool? = nil
    var browserEngine: String? = nil
    /// X's H.264 video on Chromium is translated to AV1 so X's own player plays it (`MediaTranslation`). Unset: on.
    var chromiumVideoTranslation: Bool? = nil
    /// Settings ▸ Notifications: pages may ask to send notifications (`WebNotifications`). Unset: on.
    var websiteNotifications: Bool? = nil
    /// Reader mode's look (`ReaderStyle`): "serif" or "sans", the text size in points, and "auto", "light", "sepia" or "dark".
    var readerFont: String? = nil
    /// Sites installed as apps (`WebApps`).
    var webApps: [WebApp]? = nil
    /// The language pages translate into (`PageTranslation.target`). Unset: the Mac's language.
    var translationLanguage: String? = nil
    var readerSize: Int? = nil
    var readerTheme: String? = nil
    /// The person's own sites → engine raw value (`SiteEngines`). Hosts cover their subdomains.
    var siteEngines: [String: String]? = nil
    /// Ready-made lists (`SiteEngineList.id`) → engine raw value. A list without an entry follows the default engine.
    var siteEngineLists: [String: String]? = nil

    var showPinnedGrid: Bool? = nil
    /// Essentials columns, three or four. Unset: three.
    var pinnedGridColumns: Int? = nil
    var reuseBookmarkTabs: Bool? = nil
    var bookmarkMatchDomain: Bool? = nil
    var loadBackgroundTabs: Bool? = nil
    var translucentSidebar: Bool? = nil
    /// The shown sidebar is a rail of icons (`SidebarRail`) instead of the full list. Unset: full.
    var sidebarCompact: Bool? = nil
    /// Top Tabs: where tab groups show (`GroupPlacement`). Unset: the tab row.
    var groupPlacement: GroupPlacement? = nil
    /// The Sidebar layout shows ungrouped tabs as tabs above the page instead of sidebar rows. Unset: off.
    var sidebarTopTabs: Bool? = nil
    /// Retired: the sidebar's shortcut rows (on, which rows, and the essentials grid above them). Read once from an older
    /// session and converted to pinned tabs and toolbar controls (`convertSidebarShortcuts`), then cleared.
    var sidebarShortcuts: Bool? = nil
    var sidebarShortcutItems: [String]? = nil
    var pinnedGridAboveShortcuts: Bool? = nil
    /// The small card shown after resting on a tab, and whether it carries a page thumbnail. Unset: both on.
    var tabHoverPreviews: Bool? = nil
    var tabPreviewThumbnails: Bool? = nil
    /// When links open in Peek (`LinkPeek`). Unset: Shift-click only.
    var linkPeek: LinkPeek? = nil
    /// With Automatic: links to other sites from pinned tabs (unset: on), from search results (unset: on), and every
    /// link that would open a new tab (unset: off).
    var peekPinnedLinks: Bool? = nil
    var peekSearchResults: Bool? = nil
    var peekNewTabLinks: Bool? = nil
    /// Each site's camera and microphone choice (`SitePermissions`), by host. Unset: ask.
    var sitePermissions: [String: SitePermissions]? = nil
    /// Full screen uses the whole display, around the camera housing, instead of starting below it. Unset: off.
    var fullScreenUnderNotch: Bool? = nil
    /// Top Tabs: how the address bar sits under the tabs (`TabsAddressStyle`). Unset: Full Width.
    var tabsAddressStyle: TabsAddressStyle? = nil
    /// Sidebar layout: the address bar sits above the page, the top of its card, instead of in the sidebar (Settings ▸
    /// Appearance ▸ Layout). Unset: in the sidebar.
    var addressAbovePage: Bool? = nil
    /// That bar's style. Unset: Full Width, like Chrome's address bar over the page with vertical tabs.
    var pageBarStyle: TabsAddressStyle? = nil
    /// Shortcuts the person changed (Settings ▸ General ▸ Keyboard Shortcuts), by menu command id (`KeyBindings`). An
    /// empty key removes a command's shortcut. Unset: the built-in ones.
    var keyBindings: [String: KeyCombo]? = nil
    /// Ikago Home's sections (Customize on the page). Unset: shown.
    var homeShowsFavorites: Bool? = nil
    var homeShowsFrequent: Bool? = nil
    /// Ikago Home's background (`HomeBackground`): a picked colour (0xRRGGBB), the person's own image (saved beside the
    /// session), and blur. Unset: the page colour, no blur.
    var homeBackgroundColor: UInt32? = nil
    var homeBackgroundImage: Bool? = nil
    var homeBackgroundBlur: Bool? = nil
    /// A hidden sidebar slides in when the pointer reaches the window's edge. Unset: on.
    var sidebarEdgePeek: Bool? = nil
    /// How the icon sidebar responds to the pointer (`RailHoverEffect`). Unset: no effect.
    var railHover: RailHoverEffect? = nil
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
    var trackerExceptions: [String]? = nil
    var blockTrackers: Bool? = nil
    var blockThirdPartyCookies: Bool? = nil
    var fraudulentWebsiteWarning: Bool? = nil
    /// Shows the key in sign-in fields that opens Apple's Passwords panel.
    var passwordAutoFill: Bool? = nil
    /// "ikago" fills from Ikago's own vault, "apple" from Apple Passwords (WebKit only). Unset: Ikago's
    /// vault once something was imported into it, otherwise Apple Passwords. Chromium always uses the vault.
    var passwordSource: String? = nil
    /// Ikago Passwords opens the list of logins when a sign-in field is clicked or tabbed into; off, the key
    /// in the field opens it. Unset: on.
    var passwordSuggestOnFocus: Bool? = nil
    /// Offers to save or update a login after signing in (Ikago Passwords). Unset: on.
    var passwordOfferSave: Bool? = nil
    /// Offers a generated strong password in new-password fields, saved in Ikago Passwords. Unset: on.
    var passwordSuggestStrong: Bool? = nil
    /// Fills saved addresses into address forms (Settings ▸ Autofill). Unset: on.
    var autofillAddresses: Bool? = nil
    /// Fills saved cards into payment forms, with Touch ID for each. Unset: on.
    var autofillCards: Bool? = nil
    /// Offers to save an address or card after a form with one is submitted. Unset: on.
    var autofillOfferSave: Bool? = nil
    /// Lets agents drive Ikago through its MCP server on this Mac (Settings ▸ Agents). Unset: off.
    var agentAccess: Bool? = nil
    /// Lets agents list and use the person's own open tabs, not only their own. Unset: off.
    var agentUsesOpenTabs: Bool? = nil
    /// Lets agents run their own scripts in a page (in Ikago's isolated world). Unset: off.
    var agentAllowsScripts: Bool? = nil
    /// Lets agents take consequential actions (buying, paying, sending, posting, deleting) without asking each time. They
    /// still never type passwords or card numbers. Unset: they ask.
    var agentActsWithoutAsking: Bool? = nil
    /// The agent server's port on 127.0.0.1. Unset: 47811.
    var agentPort: Int? = nil
    /// Registrable domains the person chose "Never for This Site" for.
    var passwordNeverSave: [String]? = nil
    /// Shows Safari's tabs and Tab Groups from the person's other devices (Devices control). Unset: off.
    var safariDeviceTabs: Bool? = nil
    /// Handoff of the current page to and from nearby devices. Unset: off.
    var handoff: Bool? = nil
    /// HTTPS-only mode still lets localhost/loopback use HTTP (development servers).
    var httpsAllowLocal: Bool? = nil
    /// Extra hosts that may use HTTP, comma- or space-separated (subdomains included).
    var httpsExceptions: String? = nil
    var clearDataOnQuit: Bool? = nil
    var resourcePolicyName: String? = nil
    /// Legacy session fields. Idle time no longer triggers page unloading.
    var hibernationEnabled = false
    var hibernationMinutes = 30
    var protectPinnedTabs = true
    var hibernationExceptions = ""
    var showSwitchToTabSuggestions: Bool? = nil
    var searchEngineAutocomplete: Bool? = nil
    var groupLabelStyle: String? = nil
    var showBookmarksBar: Bool? = nil
    var sidebarBookmarksExpanded: Bool? = nil
    var newTabPosition: String? = nil
    var linkTabPosition: String? = nil

    var validated: Self {
        var copy = self
        copy.hibernationMinutes = min(1440, max(1, hibernationMinutes))
        copy.hibernationExceptions = String(hibernationExceptions.prefix(4096))
        copy.httpsExceptions = httpsExceptions.map { String($0.prefix(4096)) }
        if httpsDefaultApplied != true { copy.forceHTTPS = true; copy.httpsDefaultApplied = true }
        copy.trackerExceptions = trackerExceptions.map { Array($0.prefix(200)).filter { !$0.isEmpty && $0.range(of: #"^[a-zA-Z0-9.-]+$"#, options: .regularExpression) != nil } }
        copy.downloadSites = downloadSites.map { Array($0.prefix(2000)) }
        copy.siteSafetyExceptions = siteSafetyExceptions.map { Array($0.prefix(2000)) }
        copy.pinnedGridColumns = pinnedGridColumns.map { $0 >= 4 ? 4 : 3 }
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

    /// Whether a page at `url` is secure enough for passwords, autofill and notifications: HTTPS, or a page on this Mac
    /// (`localhost`, `*.localhost`, `127.x`, `::1`), which browsers treat as secure too.
    static func isSecurePage(_ url: URL?) -> Bool {
        guard let url, let host = url.host?.lowercased(), !host.isEmpty else { return false }
        return url.scheme?.lowercased() == "https" || isLoopback(host)
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

