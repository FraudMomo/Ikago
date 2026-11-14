import AppKit
import SwiftUI

/// Embeds the AppKit web-content view (tabs, split panes) in the SwiftUI layout.
struct ContentHost: FillingViewRepresentable {
    let view: NSView
    let state: BrowserState

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        attach(to: container)
        return container
    }

    /// There is one host, so it always holds the page; reattach in case anything else borrowed the view.
    func updateNSView(_ container: NSView, context: Context) {
        attach(to: container)
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
