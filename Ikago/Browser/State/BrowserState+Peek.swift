import Foundation

/// When a clicked link opens in Peek (Settings ▸ Tabs ▸ Peek).
enum LinkPeek: String, Codable, CaseIterable, Identifiable {
    case off, shiftClick, automatic
    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: "Off"
        case .shiftClick: "Shift-Click"
        case .automatic: "Automatically"
        }
    }
}

/// How a link was clicked: with Shift, as a link that opens a new tab (target=_blank), or as a plain link.
enum PeekTrigger { case shiftClick, newTabLink, link }

extension BrowserState {
    /// Whether `url`, clicked in `tab` showing `pageURL`, opens in Peek. Shift-click peeks unless Peek is off; with
    /// Automatic, so do links to another site from a pinned tab or a search results page, and, if chosen, every link
    /// that would open a new tab.
    func peeks(_ url: URL, trigger: PeekTrigger, in tab: TabItem, pageURL: String) -> Bool {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return false }
        let mode = browserPreferences.linkPeek ?? .shiftClick
        if trigger == .shiftClick { return mode != .off }
        guard mode == .automatic else { return false }
        let preferences = browserPreferences
        if trigger == .newTabLink, preferences.peekNewTabLinks == true { return true }
        guard Self.otherSite(url, from: pageURL) else { return false }
        if tab.pinned, preferences.peekPinnedLinks != false { return true }
        return OmniboxURL.searchTerms(pageURL) != nil && preferences.peekSearchResults != false
    }

    private static func otherSite(_ url: URL, from pageURL: String) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        guard let from = URLComponents(string: pageURL)?.host?.lowercased() else { return true }
        return PublicSuffix.registrableDomain(host) != PublicSuffix.registrableDomain(from)
    }
}
