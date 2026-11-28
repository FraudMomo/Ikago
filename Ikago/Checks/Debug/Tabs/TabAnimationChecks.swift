#if DEBUG
import AppKit

/// Switching tabs is instant: the page area never runs a fade, for one page or a split.
@MainActor
enum TabAnimationChecks {
    static func run() async {
        var failures = 0
        func check(_ value: Bool, _ title: String) {
            print("IKTEST tabanimation \(value ? "PASS" : "FAIL") \(title)")
            if !value { failures += 1 }
        }
        let surface = WebTabContainerView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let window = NSWindow(contentRect: surface.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = surface
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        try? await Task.sleep(for: .milliseconds(100))
        let a = NSView(), b = NSView()
        surface.show([(id: "a", view: a)], layout: .columns)
        surface.show([(id: "b", view: b)], layout: .columns)
        check(surface.layer?.animation(forKey: "transition") == nil && surface.shownIDs == ["b"], "a tab switch shows the page at once")
        surface.show([(id: "a", view: a), (id: "b", view: b)], layout: .rows)
        check(surface.shownIDs == ["a", "b"] && surface.layer?.animation(forKey: "transition") == nil, "a split shows at once")
        print("IKTEST tabanimationchecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }
}
#endif
