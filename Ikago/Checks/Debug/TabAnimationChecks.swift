#if DEBUG
import AppKit
import SwiftUI
import QuartzCore

@MainActor
enum TabAnimationChecks {
    static func run() async {
        var failures = 0
        func check(_ value: Bool, _ title: String) {
            print("IKTEST tabanimation \(value ? "PASS" : "FAIL") \(title)")
            if !value { failures += 1 }
        }
        let root = FileManager.default.temporaryDirectory.appending(path: "IkagoAnimations-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let state = BrowserState(store: SessionStore(directory: root))
        check(state.tabHighlightStyle == .slide && state.browserPreferences.instantTabSwitching != true, "legacy defaults retain slide and page fade")
        let surface = WebTabContainerView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let window = NSWindow(contentRect: surface.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = surface
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        try? await Task.sleep(for: .milliseconds(100))
        let a = NSView(), b = NSView()
        surface.show([(id: "a", view: a)], layout: .columns)
        surface.show([(id: "b", view: b)], layout: .columns)
        check(surface.layer?.animation(forKey: "transition") != nil, "normal switching installs page fade")
        surface.show([(id: "a", view: a)], layout: .columns, animate: false)
        check(surface.layer?.animation(forKey: "transition") == nil && surface.shownIDs == ["a"], "instant switch shows the page without fade")
        surface.show([(id: "b", view: b)], layout: .columns)
        surface.show([(id: "b", view: b)], layout: .columns, animate: false)
        check(surface.layer?.animation(forKey: "transition") == nil, "enabling instant mode cancels an in-flight fade")
        surface.show([(id: "a", view: a), (id: "b", view: b)], layout: .rows, animate: false)
        check(surface.shownIDs == ["a", "b"] && surface.layer?.animation(forKey: "transition") == nil, "split arrangement respects instant mode")
        for style in TabHighlightStyle.allCases {
            state.tabHighlightStyle = style
            state.browserPreferences.instantTabSwitching = true
            state.saveNow()
            let restored = BrowserState(store: SessionStore(directory: root))
            check(restored.tabHighlightStyle == style && restored.browserPreferences.instantTabSwitching == true, "\(style.rawValue) and independent page toggle survive restore")
        }
        check(TabHighlightStyle.none.animation == nil && TabHighlightStyle.spring.animation != nil, "none disables highlight animation; spring has motion")
        state.browserPreferences.tabHighlightStyle = "future-style"
        check(state.tabHighlightStyle == .slide, "unknown style falls back safely")
        print("IKTEST tabanimationchecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }
}
#endif
