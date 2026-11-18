#if DEBUG
import AppKit
import Foundation

/// The sidebar changing form (Full, Icons, Hidden) resizes the page once, not every frame, on both engines: during the
/// motion the page's right edge stays put on screen and it is resized at most twice; afterwards it fills its card and
/// the engine lays it out at that width (`innerWidth`). See `ContentHost`.
@MainActor
enum SidebarMotionChecks {
    static func run(_ browser: BrowserWindowController, base: String) async {
        var failures = 0
        func check(_ value: Bool, _ title: String) {
            print("IKTEST sidebarmotion \(value ? "PASS" : "FAIL") \(title)")
            if !value { failures += 1 }
        }
        func pause(_ ms: Int) async { try? await Task.sleep(for: .milliseconds(ms)) }
        let state = browser.state
        state.browserPreferences.sidebarCompact = nil
        state.sidebarVisible = true
        _ = state.newTab(url: base + "/find.html?motion")
        await pause(3000)
        guard let page = browser.activeController?.page, let window = browser.window else { return finish(failures) }
        let engine = page is CEFWebTab ? "chromium" : "webkit"
        func screenRight() -> CGFloat { page.contentView.convert(page.contentView.bounds, to: nil).maxX }
        func width() -> CGFloat { page.contentView.bounds.width }
        func inner() async -> CGFloat { CGFloat((try? await page.callAsync("return window.innerWidth") as? NSNumber)?.doubleValue ?? -1) }

        for (name, change) in [("to icons", { browser.cycleSidebar() }), ("to hidden", { browser.cycleSidebar() }), ("to full", { browser.cycleSidebar() })] {
            let right = screenRight()
            var widths: Set<CGFloat> = [width()]
            var edgeMoved = false
            change()
            // Watch the motion frame by frame.
            for _ in 0..<40 {
                await pause(16)
                widths.insert(width())
                if abs(screenRight() - right) > 1 { edgeMoved = true }
            }
            await pause(400)
            let container = page.contentView.superview?.superview  // page → content view → host container
            let fills = window.contentView.map { _ in abs(page.contentView.convert(page.contentView.bounds, to: nil).maxX - right) <= 1 } ?? false
            let laidOut = await inner()
            check(!edgeMoved, "\(engine) \(name): the page's right edge stays put during the motion")
            check(widths.count <= 3, "\(engine) \(name): the page is resized at most twice, not every frame (\(widths.count - 1) sizes)")
            check(fills && container != nil, "\(engine) \(name): afterwards the page fills its card")
            check(abs(laidOut - width()) <= 2, "\(engine) \(name): the engine lays the page out at its width (\(Int(laidOut)) vs \(Int(width())))")
        }
        finish(failures)
    }

    private static func finish(_ failures: Int) {
        print("IKTEST sidebarmotionchecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }
}
#endif
