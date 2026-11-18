import AppKit

/// Hosts the tab's web view; autoresizes with its split pane.
final class TabHostView: NSView {
    /// Pointer entered or left the pane (the split header shows on hover).
    var onHover: ((Bool) -> Void)?
    /// The pointer moved inside the pane, in this view's coordinates (the split header follows the top edge).
    var onMove: ((NSPoint) -> Void)?
    /// The pane runs along the content's top edge (Top Tabs squares those tops under the address bar).
    var touchesTop = true

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
