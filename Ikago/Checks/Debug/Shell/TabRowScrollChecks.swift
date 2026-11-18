#if DEBUG
import AppKit

/// The Top Tabs row scrolled with the trackpad: a scroll the person makes stays where they left it while the row
/// redraws (a page's title changing, a tab hovered), and is never pulled back to the active tab mid-gesture.
@MainActor
enum TabRowScrollChecks {
    static func run(_ browser: BrowserWindowController) async {
        var failures = 0
        func check(_ value: Bool, _ title: String) {
            print("IKTEST tabrowscroll \(value ? "PASS" : "FAIL") \(title)")
            if !value { failures += 1 }
        }
        func settle(_ ms: Int = 400) async { try? await Task.sleep(for: .milliseconds(ms)) }
        let state = browser.state
        let original = state.snapshot()
        defer { state.apply(original) }
        LayoutSwitch.set(tabs: true, state: state)
        var opened: [TabItem] = []
        for index in 0..<30 { if let tab = state.newTab(url: "about:blank#\(index)") { opened.append(tab) } }
        guard let first = opened.first else { return finish(failures) }
        state.select(first.id)
        await settle(1200)
        guard let scroll = row(in: browser.window?.contentView) else { check(false, "the tab row scrolls"); return finish(failures) }
        let start = scroll.contentView.bounds.minX

        // Where a trackpad swipe leaves the row (synthetic swipes don't reach SwiftUI's scroll view).
        scroll.contentView.scroll(to: NSPoint(x: start + 600, y: scroll.contentView.bounds.minY))
        scroll.reflectScrolledClipView(scroll.contentView)
        await settle(500)
        let scrolled = scroll.contentView.bounds.minX
        check(scrolled > start + 200, "the row scrolls away from the active tab (from \(Int(start)) to \(Int(scrolled)))")

        // The row redraws while the active tab is out of view: the scroll stays put.
        for (index, tab) in opened.dropFirst().prefix(5).enumerated() {
            state.updateTitle(tabID: tab.id, title: "Renamed \(index)")
            await settle(120)
        }
        await settle(500)
        let after = scroll.contentView.bounds.minX
        check(abs(after - scrolled) < 1, "titles changing don't pull the row back to the active tab (\(Int(scrolled)) → \(Int(after)))")

        // Selecting a tab out of view still reveals it.
        state.select(first.id); await settle(100)
        state.select(opened[29].id); await settle(800)
        let revealed = scroll.contentView.bounds.maxX >= (scroll.documentView?.bounds.width ?? 0) - 60
        check(revealed, "selecting a tab out of view scrolls it into view")
        finish(failures)
    }

    /// Scrolls the row frame by frame (as a swipe does, including past both ends like a rubber band) and reports
    /// frames where something else moved it, and the CPU the app spent per frame.
    static func scrollProbe(_ browser: BrowserWindowController) async {
        let state = browser.state
        LayoutSwitch.set(tabs: true, state: state)
        for index in 0..<30 { _ = state.newTab(url: "about:blank#\(index)") }
        if let first = state.spaceTabs.first(where: { !$0.pinned }) { state.select(first.id) }
        try? await Task.sleep(for: .milliseconds(1500))
        guard let window = browser.window, let scroll = row(in: window.contentView) else { print("IKTEST scrollprobe no row"); return }
        let clip = scroll.contentView
        let maxX = (scroll.documentView?.bounds.width ?? 0) - clip.bounds.width
        // Out to the end, 60 pt past it, back, and past the start.
        var path: [CGFloat] = []
        var x: CGFloat = 0
        while x < maxX + 60 { x += 12; path.append(x) }
        while x > -60 { x -= 12; path.append(x) }
        while x < 0 { x += 6; path.append(x) }
        var moved = 0, worst: CGFloat = 0
        let cpuStart = ProcessInfo.processInfo.systemUptime
        var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
        let cpu0 = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1e6
        for target in path {
            clip.setBoundsOrigin(NSPoint(x: target, y: clip.bounds.minY))
            scroll.reflectScrolledClipView(clip)
            try? await Task.sleep(for: .milliseconds(16))
            let now = clip.bounds.minX
            if target >= 0, target <= maxX, abs(now - target) > 0.5 { moved += 1; worst = max(worst, abs(now - target)) }
        }
        getrusage(RUSAGE_SELF, &usage)
        let cpu1 = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1e6
        let wall = ProcessInfo.processInfo.systemUptime - cpuStart
        print("IKTEST scrollprobe frames=\(path.count) moved=\(moved) worst=\(Int(worst)) cpu=\(Int((cpu1 - cpu0) / wall * 100))% perframe=\(String(format: "%.2f", (cpu1 - cpu0) / Double(path.count) * 1000))ms")
    }

    private static func finish(_ failures: Int) {
        print("IKTEST tabrowscrollchecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }

    /// The tab row: a short horizontal scroll view whose tabs are wider than it.
    private static func row(in view: NSView?) -> NSScrollView? {
        guard let view else { return nil }
        if let scroll = view as? NSScrollView, let document = scroll.documentView, scroll.frame.height < 60,
           document.frame.width > scroll.frame.width + 100 { return scroll }
        return view.subviews.lazy.compactMap { row(in: $0) }.first
    }
}
#endif
