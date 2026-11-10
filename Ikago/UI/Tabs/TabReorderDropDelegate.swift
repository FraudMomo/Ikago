import SwiftUI
import UniformTypeIdentifiers

/// Preview a fixed before/after boundary. The order changes once, after a successful payload read.
struct TabReorderDropDelegate: DropDelegate {
    let axis: Axis
    /// The row's length along `axis`, read when the drop moves (not captured at render time).
    let length: MeasuredLength
    @Binding var preview: Bool?
    let accepts: @MainActor (String) -> Bool
    let sourceID: String?
    let perform: @MainActor (String, Bool) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.ikagoTab]) && (sourceID.map(accepts) ?? true)
    }

    func dropEntered(info: DropInfo) { updatePreview(info) }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard validateDrop(info: info) else { preview = nil; return DropProposal(operation: .cancel) }
        updatePreview(info)
        return DropProposal(operation: .move)
    }
    func dropExited(info: DropInfo) { preview = nil }

    func performDrop(info: DropInfo) -> Bool {
        defer { preview = nil }
        guard let provider = info.itemProviders(for: [.ikagoTab]).first else { return false }
        let after = isAfter(info.location)
        TabDrag.load(provider) { id in
            guard accepts(id) else { return }
            perform(id, after)
        }
        return true
    }

    private func updatePreview(_ info: DropInfo) {
        guard validateDrop(info: info) else { preview = nil; return }
        preview = isAfter(info.location)
    }
    private func isAfter(_ location: CGPoint) -> Bool {
        length.value > 0 && (axis == .horizontal ? location.x : location.y) >= length.value / 2
    }
}

/// A row's measured length, kept outside SwiftUI's observation: it changes on every frame of strip motion and
/// window resizing, and only a drop reads it, so storing it in `@State` would re-render every row each frame.
final class MeasuredLength {
    var value: CGFloat = 0
    init(_ value: CGFloat = 0) { self.value = value }
}
