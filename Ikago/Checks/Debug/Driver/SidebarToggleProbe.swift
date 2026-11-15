#if DEBUG
import AppKit

/// Hides then shows the docked sidebar and prints, each display frame, where the page and the sidebar's host are, so a
/// close that jumps instead of animating shows up as a single step. `sidebarprobe`.
@MainActor
enum SidebarToggleProbe {
    static func run(_ c: BrowserWindowController) async {
        guard let content = c.window?.contentView else { return }
        for (label, visible) in [("close", false), ("open", true)] {
            if c.state.sidebarVisible == visible { continue }
            c.toggleSidebar()
            let start = CACurrentMediaTime()
            while CACurrentMediaTime() - start < 0.45 {
                let page = c.activeController?.hostView.convert(c.activeController?.hostView.bounds ?? .zero, to: nil) ?? .zero
                let sidebar = sidebarHost(in: content)
                let frame = sidebar.flatMap { $0.window == nil ? nil : $0.convert($0.bounds, to: nil) } ?? .zero
                let materials = frostedSidebars(in: content).map { view in
                    let f = view.convert(view.bounds, to: nil)
                    return String(format: "x=%.0f w=%.0f a=%.2f", f.minX, f.width, effectiveAlpha(view))
                }
                print(String(format: "IKTEST sidebarprobe %@ %5.0fms page.x=%.1f page.w=%.1f sidebar.x=%.1f sidebar.w=%.1f alpha=%.2f",
                             label, (CACurrentMediaTime() - start) * 1000, page.minX, page.width, frame.minX, frame.width,
                             sidebar.map { effectiveAlpha($0) } ?? -1) + " material=\(materials)")
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    private static func sidebarHost(in view: NSView) -> NSView? {
        if String(describing: type(of: view)).contains("SidebarView") { return view }
        for child in view.subviews { if let found = sidebarHost(in: child) { return found } }
        return nil
    }

    /// The translucent sidebar's own frosted material (not the window's backdrop, which fills the content view).
    private static func frostedSidebars(in view: NSView) -> [NSView] {
        var found: [NSView] = []
        if let effect = view as? NSVisualEffectView, effect.material == .sidebar, effect.superview !== view.window?.contentView?.superview {
            found.append(effect)
        }
        for child in view.subviews { found += frostedSidebars(in: child) }
        return found
    }

    private static func effectiveAlpha(_ view: NSView) -> CGFloat {
        var alpha = view.alphaValue, next = view.superview
        while let parent = next { alpha *= parent.alphaValue; next = parent.superview }
        return alpha
    }
}
#endif
