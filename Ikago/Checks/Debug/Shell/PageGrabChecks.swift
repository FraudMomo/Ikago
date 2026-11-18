#if DEBUG
import AppKit

/// The page's top edge (`PageWindowGrab`): press and hold reaches as far as the chosen height, the drop-down header
/// appears after the pointer rests there and leaves after it goes, a double-click zooms unless turned off, and Off
/// leaves every click to the page.
@MainActor
enum PageGrabChecks {
    static func run(_ browser: BrowserWindowController, base: String) async {
        var failures = 0
        func check(_ value: Bool, _ title: String) {
            print("IKTEST pagegrab \(value ? "PASS" : "FAIL") \(title)")
            if !value { failures += 1 }
        }
        let state = browser.state
        let saved = (state.browserPreferences.pageGrab, state.browserPreferences.pageGrabHeight, state.browserPreferences.pageGrabZoom)
        defer {
            (state.browserPreferences.pageGrab, state.browserPreferences.pageGrabHeight, state.browserPreferences.pageGrabZoom) = saved
            print("IKTEST pagegrabchecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
        }
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

        check(grab.mode == .hold && grab.starts(event(.leftMouseDown, y: 4)), "press and hold is the default")
        check(!grab.starts(event(.leftMouseDown, y: 20)), "the default edge stops at 10 pt")
        state.browserPreferences.pageGrabHeight = 24
        check(grab.starts(event(.leftMouseDown, y: 20)) && !grab.starts(event(.leftMouseDown, y: 30)), "a taller edge reaches 24 pt")

        state.browserPreferences.pageGrab = .header
        check(!grab.starts(event(.leftMouseDown, y: 4)), "the header style doesn't grab on press")
        _ = grab.observe(event(.mouseMoved, y: 4))
        check(!grab.header.isShown, "the header waits for the pointer to rest")
        try? await Task.sleep(for: .seconds(PageGrabHeader.dwell + 0.15))
        check(grab.header.isShown && grab.header.superview === content, "the header drops down after resting on the edge")
        _ = grab.observe(event(.mouseMoved, y: 80))
        try? await Task.sleep(for: .seconds(PageGrabHeader.linger + 0.4))
        check(!grab.header.isShown && grab.header.superview == nil, "the header goes once the pointer leaves")

        let zoomed = window.isZoomed
        check(!grab.observe(event(.leftMouseDown, y: 4, clicks: 2)), "a double-click on the edge is Ikago's")
        _ = grab.observe(event(.leftMouseUp, y: 4, clicks: 2))
        try? await Task.sleep(for: .milliseconds(400))
        check(window.isZoomed != zoomed, "a double-click on the edge zooms the window")
        _ = grab.observe(event(.leftMouseDown, y: 4, clicks: 2))
        _ = grab.observe(event(.leftMouseUp, y: 4, clicks: 2))
        try? await Task.sleep(for: .milliseconds(400))
        state.browserPreferences.pageGrabZoom = false
        check(grab.observe(event(.leftMouseDown, y: 4, clicks: 2)), "with zoom off the double-click stays with the page")

        state.browserPreferences.pageGrab = nil
        LayoutSwitch.set(tabs: true, state: state)
        try? await Task.sleep(for: .milliseconds(400))
        check(grab.mode == .off && !grab.starts(event(.leftMouseDown, y: 4)), "Top Tabs leaves the page's edge to the page")
        LayoutSwitch.set(tabs: false, state: state)
        try? await Task.sleep(for: .milliseconds(400))
        state.browserPreferences.pageGrab = .off
        check(!grab.starts(event(.leftMouseDown, y: 4)), "Off never grabs")
        _ = grab.observe(event(.mouseMoved, y: 4))
        try? await Task.sleep(for: .seconds(PageGrabHeader.dwell + 0.15))
        check(!grab.header.isShown, "Off shows no header")
    }
}
#endif
