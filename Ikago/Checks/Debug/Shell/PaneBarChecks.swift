#if DEBUG
import AppKit

/// Top Tabs in split view: each visible pane has its own bar and the page fills the rest of the pane; the address bar
/// above the page gives way; leaving split view removes the bars and the page fills its pane again.
@MainActor
enum PaneBarChecks {
    static func run(_ browser: BrowserWindowController) async {
        var failures = 0
        func check(_ value: Bool, _ title: String) {
            print("IKTEST panebar \(value ? "PASS" : "FAIL") \(title)")
            if !value { failures += 1 }
        }
        let state = browser.state
        LayoutSwitch.set(tabs: true, state: state)
        _ = state.newTab(url: "about:blank#left")
        _ = state.newTab(url: "about:blank#right")
        try? await Task.sleep(for: .milliseconds(800))
        browser.splitView(nil)
        try? await Task.sleep(for: .milliseconds(1200))
        let visible = state.visibleTabIDs.compactMap { browser.content.controllers[$0] }
        check(state.showsPaneBars && visible.count == 2, "split view in Top Tabs shows pane bars")
        for controller in visible {
            let host = controller.hostView
            let filled = host.subviews.filter { $0 !== controller.paneBar && $0.autoresizingMask.contains([.width, .height]) }
            check(controller.paneBar?.superview === host && controller.paneBar?.frame.maxY == host.bounds.maxY,
                  "the bar sits along the pane's top")
            check(!filled.isEmpty && filled.allSatisfy { $0.frame.maxY <= host.bounds.height - state.tabsToolbarHeight + 0.5 },
                  "the page fills the pane below its bar")
        }
        if let id = state.activeTabID { state.unsplitGroup(containing: id) }
        try? await Task.sleep(for: .milliseconds(1000))
        let alone = browser.activeController
        check(!state.showsPaneBars && alone?.paneBar == nil && alone?.hostView.barHeight == 0, "leaving split view removes the bars")
        print("IKTEST panebarchecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }
}
#endif
