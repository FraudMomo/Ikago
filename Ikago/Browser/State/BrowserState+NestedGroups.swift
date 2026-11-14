import Foundation

/// Groups inside groups (`TabFolder.parentID`). `folders` stays a flat list; these helpers read it as a tree.
extension BrowserState {
    /// The groups directly inside `parentID` in the active Space (nil: the top level, including groups whose parent
    /// is gone), in their saved order.
    func childFolders(of parentID: String?) -> [TabFolder] {
        let space = spaceFolders
        let ids = Set(space.map(\.id))
        return space.filter { folder in
            guard let parent = folder.parentID, ids.contains(parent) else { return parentID == nil }
            return parent == parentID
        }
    }

    /// Every group in the sidebar's order: each group, then the groups inside it, depth first.
    var orderedSpaceFolders: [TabFolder] {
        var result: [TabFolder] = []
        var visited = Set<String>()
        func visit(_ parent: String?) {
            for folder in childFolders(of: parent) where visited.insert(folder.id).inserted {
                result.append(folder)
                visit(folder.id)
            }
        }
        visit(nil)
        return result
    }

    /// The group and every group inside it, at any depth.
    func folderSubtreeIDs(_ id: String) -> Set<String> {
        var result: Set<String> = [id]
        var queue = [id]
        while let next = queue.popLast() {
            for child in folders where child.parentID == next && result.insert(child.id).inserted { queue.append(child.id) }
        }
        return result
    }

    /// Tabs in the group or any group inside it.
    func tabs(inSubtree folder: TabFolder) -> [TabItem] {
        let ids = folderSubtreeIDs(folder.id)
        return regularTabs.filter { $0.folderID.map(ids.contains) == true }
    }

    /// Groups `id` can move into: same Space, not itself or one of its own groups, not where it already is.
    func folderMoveTargets(for id: String) -> [TabFolder] {
        let excluded = folderSubtreeIDs(id)
        let current = folders.first { $0.id == id }?.parentID
        return orderedSpaceFolders.filter { !excluded.contains($0.id) && $0.id != current }
    }

    /// Moves a group inside another (nil: the top level). Refuses a move into itself or its own groups.
    func moveFolder(_ id: String, into parentID: String?) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        if let parentID {
            guard !folderSubtreeIDs(id).contains(parentID),
                  let parent = folders.firstIndex(where: { $0.id == parentID && $0.spaceID == folders[index].spaceID })
            else { return }
            folders[parent].isOpen = true
        }
        folders[index].parentID = parentID
        scheduleSave()
    }
}
