import AppKit
import SwiftUI

/// Embeds the AppKit web-content view (tabs, split panes) in the SwiftUI layout.
struct ContentHost: FillingViewRepresentable {
    let view: NSView
    let state: BrowserState
    /// The layout this host belongs to; each layout has its own.
    let layout: TabLayout

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        attach(to: container)
        return container
    }

    /// Switching back while a layout is still animating out revives its host without `makeNSView`.
    /// Reclaim the page here, or it leaves the window along with the other layout's host.
    func updateNSView(_ container: NSView, context: Context) {
        if state.tabLayout == layout { attach(to: container) }
    }

    private func attach(to container: NSView) {
        // A representable must own its wrapper. Returning the shared content view directly
        // lets an outgoing SwiftUI layout keep resizing it after a floating/docked switch.
        if view.superview !== container {
            view.removeFromSuperview()
            container.addSubview(view)
        }
        view.frame = container.bounds
        view.autoresizingMask = [.width, .height]
    }
}
