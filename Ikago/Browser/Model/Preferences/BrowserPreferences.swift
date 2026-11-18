import Foundation

struct BrowserPreferences: Codable, Equatable {
    var sidebarOnRight: Bool? = nil
    var sidebarLightsFollow: Bool? = nil
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
    /// Pinned tab rows stay above the scrolling tab list instead of scrolling away with it. Unset: they scroll.
    var pinnedRowsStayInView: Bool? = nil
    /// Maximum sidebar pinned-tab columns. Unset: three.
    var pinnedGridColumns: Int? = nil
    var reuseBookmarkTabs: Bool? = nil
    var bookmarkMatchDomain: Bool? = nil
    var loadBackgroundTabs: Bool? = nil
    var translucentSidebar: Bool? = nil
    /// The shown sidebar is a rail of icons (`SidebarRail`) instead of the full list. Unset: full.
    var sidebarCompact: Bool? = nil
    /// Sidebar groups as tinted cards or as a plain folder tree (`SidebarGroupStyle`). Unset: cards.
    var sidebarGroupStyle: SidebarGroupStyle? = nil
    /// Sidebar + Tabs: where tab groups show (`GroupPlacement`). Unset: both the tab row and the icon sidebar.
    var groupPlacement: GroupPlacement? = nil
    /// The Sidebar layout shows ungrouped tabs as tabs above the page instead of sidebar rows. Unset: off.
    var sidebarTopTabs: Bool? = nil
    /// A Space header and rows for the assistant, bookmarks and history at the top of the sidebar. Unset: off.
    var sidebarShortcuts: Bool? = nil
    /// Which shortcut rows show, in order (`SidebarShortcut` raw values). Unset: Assistant, Bookmarks, History.
    var sidebarShortcutItems: [String]? = nil
    /// The Space's name above the shortcuts. Unset: shown.
    var sidebarSpaceName: Bool? = nil
    /// The pinned-tab grid sits above the shortcut rows instead of below them. Unset: below.
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
    /// Moving the window from the page's top edge (`PageGrabMode`, `PageWindowGrab`). Unset: press and hold.
    var pageGrab: PageGrabMode? = nil
    /// How far down from the page's top the edge reaches, in points (`PageGrabMode.heights`). Unset: 10.
    var pageGrabHeight: Double? = nil
    /// Double-clicking the page's top edge or its header zooms the window. Unset: on.
    var pageGrabZoom: Bool? = nil
    /// Sidebar + Tabs: the address bar's height in points (`TabsBarHeight`); unset is the standard 36.
    var tabsBarHeight: Double? = nil
    /// Sidebar + Tabs: how the address bar sits under the tabs (`TabsAddressStyle`). Unset: centred.
    var tabsAddressStyle: TabsAddressStyle? = nil
    /// A hidden sidebar slides in when the pointer reaches the window's edge. Unset: on.
    var sidebarEdgePeek: Bool? = nil
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
    var instantTabSwitching: Bool? = nil
    var tabHighlightStyle: String? = nil
    var groupLabelStyle: String? = nil
    var showGroupTabCounts: Bool? = nil
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
        copy.pinnedGridColumns = pinnedGridColumns.map { min(8, max(2, $0)) }
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

/// How the page's top edge moves the window: not at all, after a brief press and hold, or with a small header that
/// drops down while the pointer rests there.
enum PageGrabMode: String, Codable, CaseIterable {
    case off, hold, header

    static let defaultHeight = 10.0
    static let heights = 4.0...32.0

    var title: String {
        switch self {
        case .off: "Off"
        case .hold: "Press and Hold"
        case .header: "Drop-Down Header"
        }
    }
}

/// Sidebar + Tabs: how tall the address bar under the tabs is.
enum TabsBarHeight: Double, CaseIterable {
    case compact = 30, standard = 36, large = 44

    var name: String {
        switch self {
        case .compact: "Compact"
        case .standard: "Standard"
        case .large: "Large"
        }
    }
}

/// A row in the sidebar's shortcuts (Settings ▸ Sidebar ▸ Space header and shortcuts).
enum SidebarShortcut: String, CaseIterable, Identifiable {
    case assistant, bookmarks, history, downloads, notes, performance, settings

    static let defaults: [SidebarShortcut] = [.assistant, .bookmarks, .history]
    var id: String { rawValue }

    var title: String {
        switch self {
        case .assistant: "Assistant"
        case .bookmarks: "Bookmarks"
        case .history: "History"
        case .downloads: "Downloads"
        case .notes: "Notes"
        case .performance: "Performance"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .assistant: "sparkles"
        case .bookmarks: "bookmark"
        case .history: "clock"
        case .downloads: "arrow.down.circle"
        case .notes: "note.text"
        case .performance: "gauge.with.dots.needle.33percent"
        case .settings: "gearshape"
        }
    }

    /// The Ikago page it opens; the assistant is a panel instead.
    var page: InternalPage? {
        switch self {
        case .assistant: nil
        case .bookmarks: .bookmarks
        case .history: .history
        case .downloads: .downloads
        case .notes: .notes
        case .performance: .performance
        case .settings: .settings
        }
    }
}

extension BrowserPreferences {
    var shortcutItems: [SidebarShortcut] {
        sidebarShortcutItems.map { $0.compactMap(SidebarShortcut.init(rawValue:)) } ?? SidebarShortcut.defaults
    }

    /// Turns one shortcut on or off, keeping the rows in `SidebarShortcut` order.
    mutating func setShortcut(_ item: SidebarShortcut, shown: Bool) {
        var set = Set(shortcutItems)
        if shown { set.insert(item) } else { set.remove(item) }
        let items = SidebarShortcut.allCases.filter(set.contains)
        sidebarShortcutItems = items == SidebarShortcut.defaults ? nil : items.map(\.rawValue)
    }
}
