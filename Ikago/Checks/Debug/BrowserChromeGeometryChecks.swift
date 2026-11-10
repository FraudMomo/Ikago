#if DEBUG
import AppKit

@MainActor
enum BrowserChromeGeometryChecks {
    static func run(_ browser: BrowserWindowController) async {
        let state = browser.state, original = state.snapshot(), size = browser.window?.contentView?.bounds.size
        var failures = 0
        func check(_ value: Bool, _ message: String) {
            print("IKTEST chromegeometry \(value ? "PASS" : "FAIL") \(message)")
            if !value { failures += 1 }
        }
        defer {
            browser.dismissCommandPalette(); state.apply(original)
            if let size { browser.window?.setContentSize(size) }
        }
        BookmarkBarChecks.seed(browser)
        state.showsBookmarksBar = false; state.showsTopBarEssentials = false
        for layout in [TabLayout.horizontal] {
            state.tabLayout = layout
            for floating in [false, true] {
                state.barRounded = floating
                for width in [1100.0, 600.0] {
                    browser.window?.setContentSize(NSSize(width: width, height: 750))
                    try? await Task.sleep(for: .milliseconds(300))
                    guard let window = browser.window, let root = window.contentView else { continue }
                    let toolbar = LayoutChecks.frames["top-toolbar"]
                    for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                        guard let button = window.standardWindowButton(kind) else { continue }
                        let bounds = root.convert(button.bounds, from: button)
                        let topCenter = root.isFlipped ? bounds.midY : root.bounds.maxY - bounds.midY
                        check(toolbar.map { abs($0.midY - topCenter) <= 0.5 } == true,
                              "\(layout)/floating=\(floating)/\(Int(width)) native button \(kind.rawValue) aligns with toolbar center")
                    }
                }
            }
            state.barRounded = false
            browser.window?.setContentSize(NSSize(width: 1100, height: 750))
            try? await Task.sleep(for: .milliseconds(300))
            state.newTabMode = .commandBar; state.addressStyle = .integrated
            browser.newTab()
            try? await Task.sleep(for: .milliseconds(60))
            let first = LayoutChecks.frames["active-tab"]
            try? await Task.sleep(for: .milliseconds(240))
            let settled = LayoutChecks.frames["active-tab"]
            print("IKTEST insertion frames layout=\(layout) first=\(String(describing: first)) settled=\(String(describing: settled))")
            check(first.flatMap { a in settled.map { abs(a.minX - $0.minX) < 1 && abs(a.width - $0.width) < 1 } } == true,
                  "\(layout) tab insertion does not leave a spring relayout in flight")
            browser.dismissCommandPalette()
        }
        print("IKTEST chromegeometrychecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }
}
#endif
