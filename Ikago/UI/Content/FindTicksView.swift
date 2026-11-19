import AppKit

/// Find in page's marks along the page's right edge: where every match sits down the page, the selected one stronger,
/// as ticks along the scroll bar. Drawn by Ikago over WebKit pages (Chromium draws its own). Plain AppKit on the
/// tab's host view, like the link status pill; it never takes clicks.
final class FindTicksView: NSView {
    private var ticks: [Double] = []
    private var active: Double?
    static let width: CGFloat = 6

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    init() {
        super.init(frame: .zero)
        autoresizingMask = [.minXMargin, .height]
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func show(_ ticks: [Double], active: Double?, in host: NSView) {
        self.ticks = ticks
        self.active = active
        frame = NSRect(x: host.bounds.width - Self.width - 2, y: 0, width: Self.width, height: host.bounds.height)
        isHidden = ticks.isEmpty
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        // Kept clear of the page card's rounded corners at the top and bottom.
        let track = bounds.insetBy(dx: 0, dy: 10)
        NSColor.systemYellow.withAlphaComponent(0.85).setFill()
        for tick in ticks {
            NSBezierPath(roundedRect: NSRect(x: 1, y: track.minY + track.height * tick - 1, width: bounds.width - 2, height: 2),
                         xRadius: 1, yRadius: 1).fill()
        }
        if let active {
            NSColor.systemOrange.setFill()
            NSBezierPath(roundedRect: NSRect(x: 0, y: track.minY + track.height * active - 1.5, width: bounds.width, height: 3),
                         xRadius: 1.5, yRadius: 1.5).fill()
        }
    }
}
