#if DEBUG
import AppKit

/// The page's top edge (`PageWindowGrab`): a press within its 20 pt is the window's, below it the page's; a
/// double-click on it zooms the window; Top Tabs leaves every click to the page.
@MainActor
enum PageGrabChecks {
    static func run(_ browser: BrowserWindowController, base: String) async {
        var failures = 0
        func check(_ value: Bool, _ title: String) {
            print("IKTEST pagegrab \(value ? "PASS" : "FAIL") \(title)")
            if !value { failures += 1 }
        }
        let state = browser.state
        defer { print("IKTEST pagegrabchecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)") }
        browser.open(base + "/login.html", inNewTab: true)
        for _ in 0..<250 where state.activeTab?.isLoading != false { try? await Task.sleep(for: .milliseconds(20)) }
        try? await Task.sleep(for: .milliseconds(300))
        guard let grab = browser.pageWindowGrab, let window = browser.window else { return check(false, "the page grab is running") }
        let content = browser.content.view
        func event(_ type: NSEvent.EventType, y: CGFloat, clicks: Int = 1) -> NSEvent {
            let point = CGPoint(x: content.bounds.midX, y: content.isFlipped ? y : content.bounds.height - y)
            return NSEvent.mouseEvent(with: type, location: content.convert(point, to: nil), modifierFlags: [],
                                      timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                      context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)!
        }

        check(grab.starts(event(.leftMouseDown, y: 4)) && grab.starts(event(.leftMouseDown, y: 18)), "the top 20 pt move the window")
        check(!grab.starts(event(.leftMouseDown, y: 26)), "below them the page keeps its press")

        let zoomed = window.isZoomed
        check(!grab.observe(event(.leftMouseDown, y: 4, clicks: 2)), "a double-click on the edge is Ikago's")
        _ = grab.observe(event(.leftMouseUp, y: 4, clicks: 2))
        try? await Task.sleep(for: .milliseconds(400))
        check(window.isZoomed != zoomed, "a double-click on the edge zooms the window")
        _ = grab.observe(event(.leftMouseDown, y: 4, clicks: 2))
        _ = grab.observe(event(.leftMouseUp, y: 4, clicks: 2))
        try? await Task.sleep(for: .milliseconds(400))

        LayoutSwitch.set(tabs: true, state: state)
        try? await Task.sleep(for: .milliseconds(400))
        check(!grab.active && !grab.starts(event(.leftMouseDown, y: 4)), "Top Tabs leaves the page's edge to the page")
        check(grab.observe(event(.leftMouseDown, y: 4, clicks: 2)), "and its double-clicks")
        _ = grab.observe(event(.leftMouseUp, y: 4, clicks: 2))
        LayoutSwitch.set(tabs: false, state: state)
        try? await Task.sleep(for: .milliseconds(400))
    }
}
#endif
