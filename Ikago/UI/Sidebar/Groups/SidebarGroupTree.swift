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
    /// `roots`: the top-level groups to build (the block above the tabs unless given).
    @MainActor static func tree(state: BrowserState, groups: SidebarGroups, anchors: [String: [TabItem]],
                                activeID: String?, seen: inout Set<String>, roots: [TabFolder]? = nil) -> [GroupEntry] {
        func make(_ folder: TabFolder, depth: Int, seen: inout Set<String>) -> GroupEntry {
            let own = groups.tabs(in: folder.id)
            var children: [GroupEntry] = []
            if depth < 8 {
                for child in state.childFolders(of: folder.id) where child.isClosed != true { children.append(make(child, depth: depth + 1, seen: &seen)) }
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
        for folder in roots ?? state.blockFolders { result.append(make(folder, depth: 0, seen: &seen)) }
        return result
    }
}

/// A run of the loose tabs, or a group placed among them (`BrowserState.looseEntries`), as the sidebar lists them.
enum LooseSegment: Identifiable {
    /// Tabs after the group named by `after` (or at the start).
    case tabs(after: String, items: [TabListItem])
    case group(GroupEntry)

    var id: String {
        switch self {
        case .tabs(let after, _): "tabs-after-" + after
        case .group(let entry): "group-" + entry.id
        }
    }
    var visibleItems: [TabListItem] {
        switch self {
        case .tabs(_, let items): items
        case .group(let entry): entry.visibleItems
        }
    }
    var order: [String] {
        switch self {
        case .tabs(_, let items): items.map(\.id)
        case .group(let entry): entry.order
        }
    }

    /// The loose part of the list, groups placed among the tabs included. `tabsShown` false (Top Tabs, whose tab row has
    /// the loose tabs): only the placed groups.
    @MainActor static func build(state: BrowserState, groups: SidebarGroups, anchors: [String: [TabItem]], activeID: String?,
                                 tabsShown: Bool, seen: inout Set<String>) -> [LooseSegment] {
        var segments: [LooseSegment] = []
        var run: [TabItem] = [], after = "start"
        func flush(_ seen: inout Set<String>) {
            if !run.isEmpty || segments.isEmpty { segments.append(.tabs(after: after, items: state.listItems(run, seen: &seen))) }
            run = []
        }
        for entry in state.looseEntries {
            switch entry {
            case .tab(let tab): if tabsShown { run.append(tab) }
            case .folder(let folder):
                flush(&seen)
                if let group = GroupEntry.tree(state: state, groups: groups, anchors: anchors, activeID: activeID, seen: &seen,
                                               roots: [folder]).first { segments.append(.group(group)) }
                after = folder.id
            }
        }
        flush(&seen)
        return segments
    }
}
