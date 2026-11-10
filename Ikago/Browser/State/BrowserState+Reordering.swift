import Foundation

extension BrowserState {
    func canReorderTab(_ id: String, relativeTo targetID: String) -> Bool {
        guard id != targetID, let moving = tab(id), let target = tab(targetID),
              moving.spaceID == activeSpaceID, target.spaceID == activeSpaceID else { return false }
        return splitGroup(of: id)?.contains(targetID) != true
    }

    /// Reorder at a visible item's boundary. Split groups move together and stay intact.
    @discardableResult
    func reorderTab(_ id: String, relativeTo targetID: String, after: Bool) -> Bool {
        guard canReorderTab(id, relativeTo: targetID), let target = tab(targetID) else { return false }
        let moving = splitGroup(of: id) ?? [id]
        let targetGroup = splitGroup(of: targetID) ?? [targetID]
        let peers = tabs.filter {
            $0.spaceID == target.spaceID && $0.pinned == target.pinned && $0.folderID == target.folderID && !moving.contains($0.id)
        }
        let boundary: String?
        if after, let last = peers.lastIndex(where: { targetGroup.contains($0.id) }) {
            boundary = peers.indices.contains(last + 1) ? peers[last + 1].id : nil
        } else {
            boundary = peers.first { targetGroup.contains($0.id) }?.id
        }
        for member in moving { move(member, before: boundary, pinned: target.pinned, folderID: target.folderID) }
        return true
    }

    @discardableResult
    func moveTabToListEnd(_ id: String) -> Bool {
        guard let moving = tab(id), moving.spaceID == activeSpaceID else { return false }
        for member in splitGroup(of: id) ?? [id] { move(member, before: nil, pinned: false) }
        return true
    }
}
