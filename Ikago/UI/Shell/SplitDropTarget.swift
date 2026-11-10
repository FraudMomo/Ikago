import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A permanently mounted native destination above WKWebView. SwiftUI drop destinations on
/// nearly-transparent colors can fall through to the embedded page during a dragging session.
struct SplitDropTarget: FillingViewRepresentable {
    let active: Bool
    let accepts: (String) -> Bool
    let onEdge: (SplitEdge?) -> Void
    let onDrop: (String, SplitEdge) -> Void

    func makeNSView(context: Context) -> SplitDropTargetView { SplitDropTargetView() }
    func updateNSView(_ view: SplitDropTargetView, context: Context) {
        view.active = active; view.accepts = accepts; view.onEdge = onEdge; view.onDrop = onDrop
    }
}

final class SplitDropTargetView: NSView {
    static let pasteboardType = NSPasteboard.PasteboardType(UTType.ikagoTab.identifier)
    var active = false
    var accepts: (String) -> Bool = { _ in false }
    var onEdge: (SplitEdge?) -> Void = { _ in }
    var onDrop: (String, SplitEdge) -> Void = { _, _ in }
    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([Self.pasteboardType])
    }
    convenience init() { self.init(frame: .zero) }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? {
        active ? super.hitTest(point) : nil
    }
    static func tabID(in pasteboard: NSPasteboard) -> String? {
        guard let data = pasteboard.data(forType: pasteboardType),
              let drag = try? JSONDecoder().decode(TabDrag.self, from: data) else { return nil }
        return drag.id
    }
    func edge(at point: NSPoint) -> SplitEdge {
        let u = point.x / max(bounds.width, 1) - 0.5
        let v = point.y / max(bounds.height, 1) - 0.5
        if abs(u) > abs(v) { return u < 0 ? .left : .right }
        return v < 0 ? .top : .bottom
    }
    private func update(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard active, let id = Self.tabID(in: sender.draggingPasteboard), accepts(id) else {
            onEdge(nil); return []
        }
        let mask = sender.draggingSourceOperationMask
        let operation: NSDragOperation = mask.contains(.move) ? .move : mask.contains(.copy) ? .copy : []
        guard !operation.isEmpty else { onEdge(nil); return [] }
        onEdge(edge(at: convert(sender.draggingLocation, from: nil)))
        return operation
    }
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { update(sender) }
    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation { update(sender) }
    override func draggingExited(_ sender: (any NSDraggingInfo)?) { onEdge(nil) }
    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let id = Self.tabID(in: sender.draggingPasteboard) else { return false }
        return accepts(id)
    }
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        defer { onEdge(nil) }
        // Decode while AppKit owns the pasteboard, independently from transient drag UI state.
        guard let id = Self.tabID(in: sender.draggingPasteboard), accepts(id) else { return false }
        onDrop(id, edge(at: convert(sender.draggingLocation, from: nil)))
        return true
    }
    override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) { onEdge(nil) }
}
