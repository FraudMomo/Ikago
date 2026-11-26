import SwiftUI
import UniformTypeIdentifiers

/// Preview a fixed before/after boundary. The order changes once, after a successful payload read.
struct TabReorderDropDelegate: DropDelegate {
    let axis: Axis
    /// The row's length along `axis`, read when the drop moves (not captured at render time).
    let length: MeasuredLength
    @Binding var preview: Bool?
    let accepts: @MainActor (String) -> Bool
    /// The tab being dragged in this window, read only while the pointer is over the row.
    let source: @MainActor () -> String?
    let perform: @MainActor (String, Bool) -> Void
    /// The window's state, so a tab dragged from another window is brought here first.
    var into: BrowserState? = nil
    /// A group dropped before or after this row (loose tabs only: a group placed among the tabs). Nil refuses groups.
    var group: (source: @MainActor () -> String?, perform: @MainActor (String, Bool) -> Void)? = nil

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.ikagoTab]) && (source().map(accepts) ?? true)
    }

    func dropEntered(info: DropInfo) { updatePreview(info) }
    /// One check per move, and the line written only when it changes side.
    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard validateDrop(info: info) else { set(nil); return DropProposal(operation: .cancel) }
        set(isAfter(info.location))
        return DropProposal(operation: .move)
    }
    func dropExited(info: DropInfo) { set(nil) }

    func performDrop(info: DropInfo) -> Bool {
        defer { preview = nil }
        if let group, let provider = info.itemProviders(for: [.ikagoGroup]).first {
            let after = isAfter(info.location)
            GroupDrag.load(provider) { id in group.perform(id, after) }
            return true
        }
        guard let provider = info.itemProviders(for: [.ikagoTab]).first else { return false }
        let after = isAfter(info.location)
        TabDrag.load(provider, into: into, reversed: after) { id in
            guard accepts(id) else { return }
            perform(id, after)
        }
        return true
    }

    private func updatePreview(_ info: DropInfo) {
        set(validateDrop(info: info) ? isAfter(info.location) : nil)
    }
    private func set(_ value: Bool?) { if preview != value { preview = value } }
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
