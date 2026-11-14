import Foundation

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
