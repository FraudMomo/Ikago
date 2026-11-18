import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A dragged tab group (by its sidebar header). Its own type, so pages and tab targets ignore it. Group targets: another
/// group's header (before, inside, after), the end of the list (top level, last), and a Space's dot in the Space bar.
struct GroupDrag: Codable {
    let id: String

    /// Item provider carrying only this type, readable only inside Ikago.
    static func provider(_ id: String) -> NSItemProvider {
        let provider = NSItemProvider()
        let data = (try? JSONEncoder().encode(GroupDrag(id: id))) ?? Data()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.ikagoGroup.identifier, visibility: .ownProcess) { done in
            done(data, nil)
            return nil
        }
        return provider
    }

    /// Reads the dragged group's id and hands it over on the main actor.
    static func load(_ provider: NSItemProvider, perform: @escaping @MainActor (String) -> Void) {
        provider.loadDataRepresentation(forTypeIdentifier: UTType.ikagoGroup.identifier) { data, _ in
            guard let data, let drag = try? JSONDecoder().decode(GroupDrag.self, from: data) else { return }
            Task { @MainActor in perform(drag.id) }
        }
    }
}

extension UTType {
    static let ikagoGroup = UTType(exportedAs: "app.ikago.group")
}

/// Where a dragged group lands on another group's header: the top edge puts it before, the middle inside, and the
/// bottom edge of a shut group after (an open group's bottom edge sits over its first row, so that is inside too).
enum GroupDropZone: Equatable {
    case before, into, after
}

/// Drops on a group's header: tabs join the group; a group goes before, into or after it.
struct FolderHeaderDropDelegate: DropDelegate {
    let folder: TabFolder
    let state: BrowserState
    let chrome: ChromeModel
    let length: MeasuredLength
    @Binding var tabTargeted: Bool
    @Binding var zone: GroupDropZone?

    func validateDrop(info: DropInfo) -> Bool {
        if info.hasItemsConforming(to: [.ikagoGroup]) {
            return chrome.draggingFolderID.map { state.canPlaceFolder($0, relativeTo: folder.id) } ?? false
        }
        return info.hasItemsConforming(to: [.ikagoTab])
    }

    func dropEntered(info: DropInfo) { update(info) }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard validateDrop(info: info) else { clear(); return DropProposal(operation: .cancel) }
        update(info)
        return DropProposal(operation: .move)
    }
    func dropExited(info: DropInfo) { clear() }

    func performDrop(info: DropInfo) -> Bool {
        let landing = zone(at: info.location)
        clear()
        if let provider = info.itemProviders(for: [.ikagoGroup]).first {
            let target = folder.id
            GroupDrag.load(provider) { id in
                chrome.endFolderDrag()
                guard state.canPlaceFolder(id, relativeTo: target) else { return }
                withAnimation(.ikago) {
                    switch landing {
                    case .into: state.moveFolder(id, into: target)
                    case .before: state.placeFolder(id, relativeTo: target, after: false)
                    case .after: state.placeFolder(id, relativeTo: target, after: true)
                    }
                }
            }
            return true
        }
        guard let provider = info.itemProviders(for: [.ikagoTab]).first else { return false }
        // The dragged tab and every selected tab with it (`TabDrag.companions`), from this window or another.
        let target = folder.id
        TabDrag.load(provider, into: state) { id in
            chrome.endTabDrag()
            guard state.tab(id) != nil else { return }
            withAnimation(.ikago) { state.moveToFolder(id, folderID: target) }
            chrome.selectedTabIDs = []
        }
        return true
    }

    private func update(_ info: DropInfo) {
        if info.hasItemsConforming(to: [.ikagoGroup]) {
            tabTargeted = false
            zone = zone(at: info.location)
        } else {
            zone = nil
            tabTargeted = true
        }
    }

    private func clear() { zone = nil; tabTargeted = false }

    private func zone(at location: CGPoint) -> GroupDropZone {
        let height = max(1, length.value)
        if location.y < height * 0.3 { return .before }
        if !folder.isOpen && location.y > height * 0.7 { return .after }
        return .into
    }
}

/// What a dragged group looks like under the pointer.
struct GroupDragPreview: View {
    let folder: TabFolder
    let colors: Palette

    var body: some View {
        HStack(spacing: 8) {
            FolderIcon(folder: folder, colors: colors, size: 13).frame(width: 16, height: 16)
            Text(folder.name).font(.system(size: 13, weight: .semibold)).lineLimit(1).foregroundStyle(colors.text)
        }
        .padding(.horizontal, 10).frame(height: 30)
        .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(colors.selected))
    }
}

/// The line a group drop draws along a header's top or bottom edge.
struct GroupInsertionLine: View {
    let colors: Palette
    var body: some View {
        Capsule().fill(colors.accent).frame(height: 2).padding(.horizontal, 8).allowsHitTesting(false)
    }
}
