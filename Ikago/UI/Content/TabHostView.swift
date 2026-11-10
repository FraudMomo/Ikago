import AppKit

/// Hosts the tab's web view; autoresizes with its split pane.
final class TabHostView: NSView {
    /// Pointer entered or left the pane (the split header shows on hover).
    var onHover: ((Bool) -> Void)?

    init() {
        super.init(frame: .zero)
        autoresizingMask = [.width, .height]
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) {
        guard let window else { onHover?(false); return }
        let point = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        if !bounds.contains(point) { onHover?(false) }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
}
