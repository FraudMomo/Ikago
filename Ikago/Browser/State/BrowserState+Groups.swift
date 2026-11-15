import Foundation

// MARK: - Folders
/// Sidebar folders: named, collapsible groups of a Space's regular tabs.
extension BrowserState {
    var groupLabelStyle: GroupLabelStyle {
        get { browserPreferences.groupLabelStyle.flatMap(GroupLabelStyle.init(rawValue:)) ?? .minimal }
        set { browserPreferences.groupLabelStyle = newValue.rawValue }
    }

    var showsGroupTabCounts: Bool {
        get { browserPreferences.showGroupTabCounts ?? true }
        set { browserPreferences.showGroupTabCounts = newValue }
    }

    /// Creates a folder in the active Space, optionally inside another group and moving `tabID` into it.
    @discardableResult
    func createFolder(named name: String, with tabID: String? = nil, parentID: String? = nil) -> TabFolder {
        var folder = TabFolder(name: name.isEmpty ? "New Group" : name, spaceID: activeSpaceID)
        if let parentID, let index = folders.firstIndex(where: { $0.id == parentID && $0.spaceID == activeSpaceID }) {
            folder.parentID = parentID
            folders[index].isOpen = true
        }
        folders.append(folder)
        if let tabID { moveToFolder(tabID, folderID: folder.id) }
        scheduleSave()
        return folder
    }

    func renameFolder(_ id: String, to name: String) {
        guard let index = folders.firstIndex(where: { $0.id == id }), !name.isEmpty else { return }
        folders[index].name = name
        scheduleSave()
    }

    func setFolderTag(_ id: String, to tag: FolderTag?) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[index].tag = tag?.rawValue
        scheduleSave()
    }

    /// An SF Symbol name or an emoji; nil goes back to the folder.
    func setFolderIcon(_ id: String, to icon: String?) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[index].icon = icon
        scheduleSave()
    }

    func toggleFolder(_ id: String) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[index].isOpen.toggle()
        scheduleSave()
    }

    /// Deletes the folder; its tabs and the groups inside it move up to its parent (loose tabs at the top level).
    func deleteFolder(_ id: String) {
        let parent = folders.first { $0.id == id }?.parentID
        for tab in tabs where tab.folderID == id { tab.folderID = parent }
        for index in folders.indices where folders[index].parentID == id { folders[index].parentID = parent }
        folders.removeAll { $0.id == id }
        scheduleSave()
    }

    /// A tab dropped on another: onto a loose tab with `makeGroup` it starts a group of the two;
    /// otherwise it takes the target's place (and its group).
    func drop(_ id: String, onto target: TabItem, makeGroup: Bool) {
        guard id != target.id else { return }
        if makeGroup, !target.pinned, target.folderID == nil {
            let folder = createFolder(named: "New Group", with: target.id)
            moveToFolder(id, folderID: folder.id)
        } else {
            move(id, before: target.id, pinned: target.pinned, folderID: target.folderID)
        }
    }

    /// Puts a tab at the end of a folder (or loose with `nil`), unpinning it if needed.
    func moveToFolder(_ tabID: String, folderID: String?) {
        move(tabID, before: nil, pinned: false, folderID: folderID)
        // Open the group and every group around it, so the moved tab is on screen.
        var next = folderID
        var steps = 0
        while let id = next, steps < 16, let index = folders.firstIndex(where: { $0.id == id }) {
            folders[index].isOpen = true
            next = folders[index].parentID
            steps += 1
        }
    }
}

// MARK: - NestedGroups
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

// MARK: - ClosedGroups
/// Closed tab groups: a closed group keeps its tabs, unloaded, so it can be reopened from the Tab menu.
/// Selecting one of its tabs reopens it. The sidebar still lists closed groups.
extension BrowserState {
    /// The active Space's closed groups, in sidebar order.
    var closedFolders: [TabFolder] { spaceFolders.filter { $0.isClosed == true } }

    /// Tab order for next/previous tab and close-neighbour selection: the sidebar's, which lists every group.
    var navigationOrder: [TabItem] { sidebarOrder }

    /// Reopens a closed group, expanded, and selects its first tab.
    func reopenFolder(_ id: String, selecting: Bool = true) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[index].isClosed = nil
        folders[index].isOpen = true
        if selecting, let first = tabs(in: folders[index]).first { activeTabID = first.id }
        scheduleSave()
    }

    /// Selecting a tab of a closed group (from history, the omnibox or the sidebar) reopens the group.
    func reopenFolderIfClosed(containing tabID: String) {
        guard let folderID = tab(tabID)?.folderID, folders.first(where: { $0.id == folderID })?.isClosed == true else { return }
        reopenFolder(folderID, selecting: false)
    }
}

// MARK: - Essentials
extension BrowserState {
    var showsPinnedGrid: Bool { browserPreferences.showPinnedGrid ?? true }
    var presentsSidebarPinGrid: Bool { showsPinnedGrid }
    var sidebarGridPinnedTabs: [TabItem] {
        pinnedTabs.filter { !$0.pinAsRow && splitGroup(of: $0.id) == nil }
    }

    /// Address-bar navigation preserves live pins. Page links remain native navigation.
    func addressNeedsNewTab(for url: String) -> Bool {
        guard let active = activeTab, active.pinned else { return false }
        return Self.pageKey(active.url) != Self.pageKey(url)
    }
}
