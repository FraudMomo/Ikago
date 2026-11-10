import Foundation

extension TabController {
    func webTab(_ page: WebTab, didFindFavicon url: URL?) {
        guard let url else { return }
        let pageURL = tab.url, persist = !isPrivate
        Task { [weak self, weak page] in
            guard await FaviconCache.shared.image(for: url, persist: persist) != nil,
                  let self, let page, self.page === page, self.tab.url == pageURL else { return }
            _ = await FaviconCache.shared.image(pageURL: pageURL, iconURL: url, persist: persist)
            // Unchanged icon: nothing new for the tab, its bookmarks or the session.
            guard self.tab.faviconURL != url else { return }
            self.tab.faviconURL = url
            if let state = self.browserState {
                for index in state.bookmarks.indices where BrowserState.pageKey(state.bookmarks[index].url) == BrowserState.pageKey(pageURL) {
                    state.bookmarks[index].favicon = url.absoluteString
                }
                state.scheduleSave()
            }
        }
    }
}
