import Foundation

// MARK: - Favicon
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

// MARK: - Media
extension TabController {
    func webTab(_ page: WebTab, didChangePlayback playback: MediaPlaybackState) {
        guard page === self.page, tab.playback != playback else { return }
        tab.playback = playback
    }
}

// MARK: - History
/// Back history across relaunch, unloading and ⌘⇧T (`TabHistory`): recorded whenever a page finishes loading, given
/// back when the page next starts. WebKit restores its own; Chromium can't, so Back walks the saved addresses
/// (`EngineHandoff.restoredBack`), each replacing the current entry so the page's own Back never points forward.
extension TabController {
    func captureHistory() {
        guard let page, !isPrivate, AddressResolver.isPageURL(tab.url) else { return }
        let restored = handoff.restoredBack, current = tab.url
        Task { [weak self, weak page] in
            guard let page, let history = await page.sessionHistory() ?? (restored.isEmpty ? nil : TabHistory()),
                  let self, self.page === page else { return }
            var merged = history
            merged.back = TabHistory.trimmed(restored + (history.back ?? []))
            merged.url = current
            guard self.tab.history != merged else { return }
            self.tab.history = merged.isEmpty ? nil : merged
            self.browserState?.scheduleSave()
        }
    }

    /// A page that hasn't loaded yet takes the tab's saved history, once, if it was recorded for the page it starts at.
    /// True when the page restored it (and its page) itself.
    func restoreHistory(into page: WebTab, destination: String) -> Bool {
        guard let history = tab.history, !isPrivate else { return false }
        tab.history = nil  // recorded again when this page finishes loading
        guard history.leads(to: destination) else { return false }
        if page.restoreHistory(history) { return true }
        handoff.restoredBack = history.back ?? []
        refreshHistoryButtons()
        return false
    }

    /// Back past the page's own history, into the saved addresses. False when there are none left.
    func goBackThroughRestored() -> Bool {
        guard !handoff.pageCanGoBack, handoff.previous == nil, handoff.previousDestination == nil,
              let url = handoff.restoredBack.popLast(), let page else { return false }
        page.replace(with: url)
        refreshHistoryButtons()
        return true
    }
}

// MARK: - Memory
extension TabController {
    /// Keep navigation history and drafts intact when recreating a tab would lose them.
    func canReleaseMemory() async -> Bool {
        // Hibernation recreates only the current URL, so retain tabs with cross-engine history.
        guard handoff.previous == nil, handoff.next == nil,
              handoff.previousDestination == nil, handoff.nextDestination == nil else { return false }
        guard let page, !page.isInspectorVisible else { return false }
        return await page.canReleaseMemory()
    }

    /// Release recreatable hidden history documents first, keeping their navigation destinations.
    func releaseParkedMemory() async {
        if let previous = handoff.previous,
           await canReleaseParked(previous), handoff.previous === previous, previous !== page {
            handoff.previousDestination = (previous.currentURL, previous.engine)
            handoff.previous = nil
            previous.tearDown()
        }
        if let next = handoff.next,
           await canReleaseParked(next), handoff.next === next, next !== page {
            handoff.nextDestination = (next.currentURL, next.engine)
            handoff.next = nil
            next.tearDown()
        }
        refreshHistoryButtons()
    }

    private func canReleaseParked(_ page: WebTab) async -> Bool {
        func idle() -> Bool {
            !page.isLoading && !page.isInspectorVisible && !page.isAudible
        }
        guard idle() else { return false }
        let url = page.currentURL
        let safe = await page.canReleaseMemory()
        return safe && idle() && page.currentURL == url
    }
}
