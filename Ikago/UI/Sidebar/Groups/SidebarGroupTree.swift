import Foundation

/// One group as the sidebar lists it, with the groups inside it (nested groups, `TabFolder.parentID`). Counts, sleep
/// and the active tab cover the whole subtree, so a closed parent still says what it holds.
struct GroupEntry: Identifiable {
    let folder: TabFolder
    let depth: Int
    /// Tabs in this group and every group inside it.
    let count: Int
    /// Every one of those tabs is closed or asleep.
    let sleeping: Bool
    let containsActive: Bool
    let items: [TabListItem]
    /// Standalone pins placed right after this group.
    let pins: [TabListItem]
    let children: [GroupEntry]
    var id: String { folder.id }

    /// Rows on screen: the group's own and its children's while it is open, then the pins after it.
    var visibleItems: [TabListItem] { (folder.isOpen ? children.flatMap(\.visibleItems) + items : []) + pins }
    /// Ids in list order, for the list's reflow animation.
    var order: [String] { [folder.id] + children.flatMap(\.order) + items.map(\.id) + pins.map(\.id) }

    /// The active Space's groups as a tree, top level first. Children are listed before the group's own tabs, as a
    /// folder lists its folders first. Depth is capped, so a damaged session with a parent loop can't recurse forever.
    @MainActor static func tree(state: BrowserState, groups: SidebarGroups, anchors: [String: [TabItem]],
                                activeID: String?, seen: inout Set<String>) -> [GroupEntry] {
        func make(_ folder: TabFolder, depth: Int, seen: inout Set<String>) -> GroupEntry {
            let own = groups.tabs(in: folder.id)
            var children: [GroupEntry] = []
            if depth < 8 {
                for child in state.childFolders(of: folder.id) { children.append(make(child, depth: depth + 1, seen: &seen)) }
            }
            let count = own.count + children.reduce(0) { $0 + $1.count }
            let ownAsleep = own.allSatisfy { $0.isUnloaded && $0.id != activeID }
            return GroupEntry(folder: folder, depth: depth, count: count,
                              sleeping: count > 0 && ownAsleep && children.allSatisfy { $0.count == 0 || $0.sleeping },
                              containsActive: own.contains { $0.id == activeID } || children.contains(where: \.containsActive),
                              items: state.listItems(own, seen: &seen), pins: state.listItems(anchors[folder.id] ?? [], seen: &seen),
                              children: children)
        }
        var result: [GroupEntry] = []
        for folder in state.childFolders(of: nil) { result.append(make(folder, depth: 0, seen: &seen)) }
        return result
    }
}
