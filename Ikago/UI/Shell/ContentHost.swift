import AppKit
import SwiftUI

/// Hosts the shared content view (every tab's page) in the SwiftUI shell.
///
/// When the sidebar animates (Full, Icons, Hidden, or the page assistant opening), SwiftUI resizes this host on every
/// frame. Passing that on made each page lay itself out about 60 times a second (measured: the page process at 37–50%
/// CPU for the whole animation), and a Chromium page must never be resized frame by frame anyway: its layers drift. So
/// while the chrome beside the page animates, the page keeps one size and stays still on screen, and the host clips it:
/// a page that will grow takes its final size at once and the shrinking sidebar uncovers it; a page that will shrink
/// keeps its size, is covered, and takes its final size once the motion ends. One resize either way.
struct ContentHost: FillingViewRepresentable {
    let view: NSView
    let state: BrowserState
    /// Width the chrome takes beside the page (sidebar, gaps, the page assistant), from the final layout.
    var sideChrome: CGFloat = 0

    final class Coordinator { var sideChrome: CGFloat? }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> ContentContainerView {
        let container = ContentContainerView()
        context.coordinator.sideChrome = sideChrome
        attach(to: container)
        return container
    }

    /// There is one host, so it always holds the page; reattach in case anything else borrowed the view.
    func updateNSView(_ container: ContentContainerView, context: Context) {
        let previous = context.coordinator.sideChrome
        context.coordinator.sideChrome = sideChrome
        if let previous, previous != sideChrome, container.bounds.width > 0,
           context.transaction.animation != nil, !context.transaction.disablesAnimations {
            // This update starts an animation from the current size to one `sideChrome - previous` narrower.
            container.holdPage(finalWidth: container.bounds.width - (sideChrome - previous),
                               radius: state.pageCornerRadius, squareTop: state.pageHasTopBar)
        }
        attach(to: container)
    }

    private func attach(to container: ContentContainerView) {
        // A representable must own its wrapper. Returning the shared content view directly
        // lets an outgoing SwiftUI layout keep resizing it after a floating/docked switch.
        if view.superview !== container {
            view.removeFromSuperview()
            container.addSubview(view)
        }
        container.content = view
        container.place()
    }
}

/// The page's host view: fills the page to its bounds, except while the chrome beside it animates (`holdPage`).
final class ContentContainerView: NSView {
    weak var content: NSView?
    /// The page's width while the host animates; nil when it simply fills the host.
    private var heldWidth: CGFloat?
    private var settle: DispatchWorkItem?
    /// How long the size must stay still before the motion counts as finished.
    private static let settleDelay: TimeInterval = 0.12
    #if DEBUG
    /// Times the page was given a new size (`AnimationProbe`); autoresizing ones while not held aren't counted.
    static var resizes = 0
    #endif

    func holdPage(finalWidth: CGFloat, radius: CGFloat, squareTop: Bool) {
        // Never narrower than now (a page about to shrink keeps its size until the end), never wider than needed.
        heldWidth = max(finalWidth, bounds.width).rounded()
        // Clip to the page card's own shape, so the edge the sidebar crosses stays rounded.
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerRadius = radius
        layer?.cornerCurve = .continuous
        layer?.maskedCorners = squareTop ? [.layerMinXMinYCorner, .layerMaxXMinYCorner] : [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        place()
        scheduleSettle()
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        place()
        if heldWidth != nil { scheduleSettle() }
    }

    override func layout() {
        super.layout()
        place()
    }

    func place() {
        guard let content else { return }
        guard let heldWidth else {
            content.autoresizingMask = [.width, .height]
            if content.frame != bounds {
                #if DEBUG
                if content.frame.size != bounds.size { Self.resizes += 1 }
                #endif
                content.frame = bounds
            }
            return
        }
        content.autoresizingMask = []
        let frame = NSRect(x: bounds.width - heldWidth, y: 0, width: heldWidth, height: bounds.height)
        if content.frame != frame {
            #if DEBUG
            if content.frame.size != frame.size { Self.resizes += 1 }
            #endif
            content.frame = frame
        }
    }

    private func scheduleSettle() {
        settle?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.heldWidth = nil
            self.layer?.masksToBounds = false
            self.layer?.cornerRadius = 0
            self.place()
        }
        settle = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay, execute: work)
    }
}
