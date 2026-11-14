import AppKit

/// A restored tab's saved Back addresses on Chromium (`TabHistory`, `TabController+History`): Back is offered, goes to
/// the saved page in place of the current entry, and the history is recorded again for the next relaunch.
@MainActor
enum CEFHistoryChecks {
    static func run(_ shell: BrowserWindowController, url: String) async throws {
        let state = shell.state
        let earlier = url + (url.contains("?") ? "&" : "?") + "earlier"
        guard let tab = state.newTab(url: url, select: false) else { throw CEFError.script("No tab for the history check.") }
        tab.history = TabHistory(back: [earlier])
        state.select(tab.id)
        try await wait { (shell.content.controller(for: tab.id)?.page as? CEFWebTab)?.isLoading == false && tab.canGoBack }
        guard let controller = shell.content.controller(for: tab.id), let page = controller.page as? CEFWebTab else {
            throw CEFError.script("The restored tab didn't start.")
        }
        controller.goBack()
        try await wait { page.currentURL == earlier && !page.isLoading }
        let entries = (try await page.devTools("Page.getNavigationHistory", [:])["entries"] as? [[String: Any]])?.count ?? 0
        guard entries == 1, !tab.canGoBack else {
            throw CEFError.script("Back through restored history stacked entries (\(entries)) or offered Back with none left.")
        }
        state.closeTab(tab.id)
    }

    private static func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<200 { if condition() { return }; try await Task.sleep(for: .milliseconds(50)) }
        throw CEFError.script("Restored history timed out.")
    }
}
