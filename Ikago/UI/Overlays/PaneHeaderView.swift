import AppKit
import UniformTypeIdentifiers

/// Native controls keep the close button independent from the drag source.
final class PaneHeaderView: NSVisualEffectView {
    let handle = PaneDragHandle()
    let closeButton = NSButton()
    var onRemove: () -> Void = {}
    var onDragBegan: () -> Void = {}
    var onDragEnded: () -> Void = {}

    init(tab: TabItem) {
        super.init(frame: .zero)
        material = .popover; blendingMode = .withinWindow; state = .active
        wantsLayer = true; layer?.cornerRadius = 13
        handle.tabID = tab.id; handle.title.stringValue = tab.displayTitle
        handle.onBegan = { [weak self] in self?.onDragBegan() }
        handle.onEnded = { [weak self] in self?.onDragEnded() }
        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Remove from Split View")
        closeButton.isBordered = false
        closeButton.target = self; closeButton.action = #selector(removePane)
        closeButton.toolTip = "Remove from Split View (keep tab open)"
        addSubview(handle); addSubview(closeButton)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        closeButton.frame = NSRect(x: max(0, bounds.width - 30), y: 2, width: 26, height: 22)
        handle.frame = NSRect(x: 10, y: 0, width: max(0, bounds.width - 42), height: 26)
    }
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
        title.font = .systemFont(ofSize: 11.5, weight: .medium)
        title.lineBreakMode = .byTruncatingTail
        addSubview(title)
        toolTip = "Drag to move this pane"
    }
    convenience init() { self.init(frame: .zero) }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    override func layout() { super.layout(); title.frame = bounds.insetBy(dx: 0, dy: 5) }
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
