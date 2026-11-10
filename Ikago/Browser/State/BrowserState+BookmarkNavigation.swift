import Foundation

extension BrowserState {
    /// Prefer the selected match, then an exact page, then (opt-in) another page on the
    /// same host. Never navigate a matching tab away from its current page or cross Spaces.
    func matchingBookmarkTab(for url: String) -> TabItem? {
        guard browserPreferences.reuseBookmarkTabs ?? true else { return nil }
        let candidates = spaceTabs.filter { tab in
            AddressResolver.isWebURL(tab.url) && (Self.pageKey(tab.url) == Self.pageKey(url)
                || (browserPreferences.bookmarkMatchDomain == true && Self.bookmarkHost(tab.url) == Self.bookmarkHost(url)))
        }
        return candidates.first { $0.id == activeTabID }
            ?? candidates.first { Self.pageKey($0.url) == Self.pageKey(url) }
            ?? candidates.first
    }

    @discardableResult
    func openBookmark(_ bookmark: Bookmark, forceNewTab: Bool = false) -> TabItem? {
        guard AddressResolver.isWebURL(bookmark.url) else { return nil }
        if !forceNewTab, let tab = matchingBookmarkTab(for: bookmark.url) {
            select(tab.id)
            return tab
        }
        return newTab(url: bookmark.url)
    }

    /// Fragment anchors share a page; paths, queries, schemes and non-default ports do not.
    static func pageKey(_ url: String) -> String {
        guard var parts = URLComponents(string: url) else { return url }
        parts.scheme = parts.scheme?.lowercased()
        parts.host = parts.host?.lowercased()
        parts.fragment = nil
        if parts.path.isEmpty { parts.path = "/" }
        if (parts.scheme == "https" && parts.port == 443) || (parts.scheme == "http" && parts.port == 80) { parts.port = nil }
        return parts.string ?? url
    }

    private static func bookmarkHost(_ url: String) -> String? { URLComponents(string: url)?.host?.lowercased() }
}
