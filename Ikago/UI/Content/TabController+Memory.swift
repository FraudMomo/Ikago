import Foundation

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
