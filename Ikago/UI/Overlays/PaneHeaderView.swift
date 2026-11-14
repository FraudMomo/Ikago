import AppKit
import UniformTypeIdentifiers

/// A split pane's handle: a small frosted pill centred at the pane's top, shown only while the pointer is near that edge
/// (`TabController.setHeaderVisible`), so it never covers the page otherwise. Its middle is a large Remove from Split
/// View button; the rest of the pill (with a grip on each side) drags the pane. Native controls keep the button
/// independent from the drag source.
final class PaneHeaderView: NSVisualEffectView {
    static let height: CGFloat = 28
    static let width: CGFloat = 92
    static let topGap: CGFloat = 6
    let handle = PaneDragHandle()
    let closeButton = NSButton()
    var onRemove: () -> Void = {}
    var onDragBegan: () -> Void = {}
    var onDragEnded: () -> Void = {}

    init(tab: TabItem) {
        super.init(frame: .zero)
        material = .hudWindow; blendingMode = .withinWindow; state = .active
        wantsLayer = true; layer?.cornerRadius = Self.height / 2; layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.5; layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        alphaValue = 0
        handle.tabID = tab.id; handle.title.stringValue = tab.displayTitle
        handle.onBegan = { [weak self] in self?.onDragBegan() }
        handle.onEnded = { [weak self] in self?.onDragEnded() }
        closeButton.image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "Remove from Split View")?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .semibold))
        closeButton.contentTintColor = .labelColor
        closeButton.isBordered = false
        closeButton.target = self; closeButton.action = #selector(removePane)
        closeButton.toolTip = "Remove from Split View (keep tab open)"
        addSubview(handle); addSubview(closeButton)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        closeButton.frame = NSRect(x: ((bounds.width - 32) / 2).rounded(), y: 1, width: 32, height: Self.height - 2)
        handle.frame = bounds
    }

    func preferredWidth(in available: CGFloat) -> CGFloat { min(Self.width, max(0, available - 24)) }
    @objc private func removePane() { onRemove() }
}

final class PaneDragHandle: NSView, NSDraggingSource {
    let title = NSTextField(labelWithString: "")
    var tabID = ""
    var onBegan: () -> Void = {}
    var onEnded: () -> Void = {}
    private var down: NSEvent?
    override init(frame: NSRect) {
        super.init(frame: frame)
        title.font = .systemFont(ofSize: 11, weight: .medium)
        title.lineBreakMode = .byTruncatingTail
        // The page itself shows which tab it is; the handle only needs grips that say it can be dragged.
        for edge in [NSLayoutConstraint.Attribute.leading, .trailing] {
            let grip = NSImageView(image: NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: nil)!
                .withSymbolConfiguration(.init(pointSize: 9, weight: .semibold))!)
            grip.contentTintColor = .tertiaryLabelColor
            grip.translatesAutoresizingMaskIntoConstraints = false
            addSubview(grip)
            NSLayoutConstraint.activate([
                grip.centerYAnchor.constraint(equalTo: centerYAnchor),
                edge == .leading ? grip.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12)
                    : grip.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            ])
        }
        toolTip = "Drag to move this pane"
    }
    convenience init() { self.init(frame: .zero) }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    override func layout() { super.layout() }
    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) == nil ? nil : self }
    override func mouseDown(with event: NSEvent) { down = event }
    override func mouseUp(with event: NSEvent) { down = nil }
    override func mouseDragged(with event: NSEvent) {
        guard let down, hypot(event.locationInWindow.x - down.locationInWindow.x, event.locationInWindow.y - down.locationInWindow.y) >= 4 else { return }
        self.down = nil
        let item = NSPasteboardItem()
        guard let data = try? JSONEncoder().encode(TabDrag(id: tabID)) else { return }
        item.setData(data, forType: NSPasteboard.PasteboardType(UTType.ikagoTab.identifier))
        let drag = NSDraggingItem(pasteboardWriter: item)
        let image = NSImage(size: bounds.size)
        image.lockFocus(); title.stringValue.draw(at: .zero, withAttributes: [.font: title.font!]); image.unlockFocus()
        drag.setDraggingFrame(bounds, contents: image)
        onBegan()
        beginDraggingSession(with: [drag], event: event, source: self)
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .move }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) { onEnded() }
}
