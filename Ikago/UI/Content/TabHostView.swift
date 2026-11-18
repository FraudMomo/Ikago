import AppKit

/// Hosts the tab's web view; autoresizes with its split pane.
final class TabHostView: NSView {
    /// Pointer entered or left the pane (the split header shows on hover).
    var onHover: ((Bool) -> Void)?
    /// The pointer moved inside the pane, in this view's coordinates (the split header follows the top edge).
    var onMove: ((NSPoint) -> Void)?
    /// The pane runs along the content's top edge (Top Tabs squares those tops under the address bar).
    var touchesTop = true
    /// The pane's own bar along its top (`PaneBar`, Top Tabs in split view); the page fills the rest.
    weak var bar: NSView?
    var barHeight: CGFloat = 0 { didSet { if oldValue != barHeight { placePage() } } }
    /// Where the page and everything that fills it go: the whole pane, less its bar.
    var pageFrame: NSRect { NSRect(x: 0, y: 0, width: bounds.width, height: max(0, bounds.height - barHeight)) }

    init() {
        super.init(frame: .zero)
        autoresizingMask = [.width, .height]
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        placePage()
    }
    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        if barHeight > 0 { placePage() }
    }

    /// Views that fill the pane's height (the page, a built-in or error page, the find ticks) stay below the bar.
    private func placePage() {
        let page = pageFrame
        for view in subviews where view !== bar && view.autoresizingMask.contains(.height) {
            var frame = view.frame
            if view.autoresizingMask.contains(.width) { frame = page } else { frame.origin.y = 0; frame.size.height = page.height }
            if view.frame != frame { view.frame = frame }
        }
        if let bar { bar.frame = NSRect(x: 0, y: page.maxY, width: bounds.width, height: barHeight) }
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseMoved(with event: NSEvent) {
        onMove?(convert(event.locationInWindow, from: nil))
        super.mouseMoved(with: event)
    }
    override func mouseExited(with event: NSEvent) {
        guard let window else { onHover?(false); return }
        let point = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        if !bounds.contains(point) { onHover?(false) }
    }

    /// Re-applies the corner mask whenever the pane is placed (`WebTabContainerView.round`).
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if superview != nil { WebTabContainerView.round(self) }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
}
