import AppKit

extension BrowserWindowController {
    @objc func showPerformance(_ sender: Any?) { openPage(.performance) }

    func performanceTabs() -> [TabPerformanceEntry] {
        state.tabs.map { tab in
            let controller = content.controller(for: tab.id)
            let page = controller?.page
            let parked = [controller?.handoff.previous, controller?.handoff.next].compactMap { $0 }.count
            return TabPerformanceEntry(id: tab.id, title: tab.displayTitle,
                engine: page?.engine.rawValue.capitalized ?? tab.engine?.rawValue.capitalized ?? "—",
                status: InternalPage(url: tab.url) != nil ? "Browser page" : page == nil ? "Unloaded"
                    : tab.isLoading ? "Loading" : state.visibleTabIDs.contains(tab.id) ? "Visible" : "Background",
                pid: page?.performanceProcessID, parked: parked)
        }
    }
}
