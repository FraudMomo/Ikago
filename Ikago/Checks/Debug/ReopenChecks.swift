#if DEBUG
import Foundation

/// ⌘⇧T brings back Ikago's own pages, never duplicates them, and skips empty split slots.
@MainActor
enum ReopenChecks {
    static func run(_ browser: BrowserWindowController) {
        let state = browser.state
        var failures = 0
        func check(_ value: Bool, _ message: String) {
            print("IKTEST reopen \(value ? "PASS" : "FAIL") \(message)")
            if !value { failures += 1 }
        }
        let settingsCount = { state.spaceTabs.filter { $0.url == InternalPage.settings.url }.count }
        browser.openPage(.settings)
        guard let settings = state.activeTab, settings.url == InternalPage.settings.url else {
            check(false, "Settings opens in a tab"); return
        }
        state.closeTab(settings.id)
        check(settingsCount() == 0, "closing Settings closes its tab")
        state.reopenClosedTab()
        check(state.activeTab?.url == InternalPage.settings.url && settingsCount() == 1, "⌘⇧T reopens a closed Settings tab")

        // Closed again, then opened another way: reopening shows the open one instead of a second copy.
        if let again = state.activeTab { state.closeTab(again.id) }
        browser.openPage(.settings)
        state.reopenClosedTab()
        check(settingsCount() == 1 && state.activeTab?.url == InternalPage.settings.url, "reopening never duplicates Settings")

        browser.openPage(.history)
        if let history = state.activeTab { state.closeTab(history.id) }
        state.reopenClosedTab()
        check(state.activeTab?.url == InternalPage.history.url, "History comes back too")

        check(!BrowserState.isReopenableInternalPage(InternalPage.splitEmpty.url) && BrowserState.isReopenableInternalPage(InternalPage.settings.url),
              "empty split slots aren't reopened; other internal pages are")
        print("IKTEST reopenchecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }
}
#endif
