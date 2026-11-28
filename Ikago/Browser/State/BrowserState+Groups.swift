import Foundation

// MARK: - Folders
/// Sidebar folders: named, collapsible groups of a Space's regular tabs.
extension BrowserState {
    var groupLabelStyle: GroupLabelStyle {
        get { browserPreferences.groupLabelStyle.flatMap(GroupLabelStyle.init(rawValue:)) ?? .minimal }
        set { browserPreferences.groupLabelStyle = newValue.rawValue }
    }

    /// Groups as color pills in tinted cards; off, a small color marker in an indented folder list (Settings ▸ Tab Groups).
    var groupsAsPills: Bool { groupLabelStyle == .colorPill }

    /// Top Tabs: where groups show. The Sidebar layout always lists them in the sidebar.
    var groupPlacement: GroupPlacement { browserPreferences.groupPlacement ?? .topBar }
    /// Group chips lead their tabs in the tab row (`TopBarGroupChip`).
    var showsGroupsInTopBar: Bool { showsSidebarTopTabs && groupPlacement != .sidebar }
    /// The icon sidebar (and the full sidebar) list groups.
    var showsGroupsInSidebar: Bool { !usesTabsLayout || groupPlacement != .topBar }


    /// Creates a folder in the active Space, optionally inside another group and moving `tabID` into it.
    @discardableResult
    func createFolder(named name: String, with tabID: String? = nil, parentID: String? = nil) -> TabFolder {
        var folder = TabFolder(name: name.isEmpty ? "New Group" : name, spaceID: activeSpaceID)
        if let parentID, let index = folders.firstIndex(where: { $0.id == parentID && $0.spaceID == activeSpaceID }) {
            folder.parentID = parentID
            folders[index].isOpen = true
        } else if let tabID, let tab = tab(tabID), tab.folderID == nil, !tab.pinned {
            // A group made from a loose tab takes that tab's place among the tabs, as in Chrome.
            let loose = looseTabs.map(\.id)
            if let position = loose.firstIndex(of: tabID) { folder.afterTabID = position > 0 ? loose[position - 1] : "" }
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

    // MARK: Groups among tabs

    /// A loose tab, or a top-level group placed among the loose tabs (`afterTabID`).
    enum LooseEntry: Identifiable {
        case tab(TabItem)
        case folder(TabFolder)
        var id: String {
            switch self {
            case .tab(let tab): tab.id
            case .folder(let folder): "folder:" + folder.id
            }
        }
    }

    /// The listed groups kept in the block above the tabs.
    var blockFolders: [TabFolder] { listedFolders.filter { $0.afterTabID == nil } }

    /// The loose tabs with the groups placed among them, in order. A group whose tab is gone counts as first.
    var looseEntries: [LooseEntry] {
        let loose = looseTabs
        let ids = Set(loose.map(\.id))
        let placed = Dictionary(grouping: listedFolders.filter { $0.afterTabID != nil }) { folder in
            folder.afterTabID.flatMap { ids.contains($0) ? $0 : nil } ?? ""
        }
        var entries = (placed[""] ?? []).map(LooseEntry.folder)
        for tab in loose {
            entries.append(.tab(tab))
            entries += (placed[tab.id] ?? []).map(LooseEntry.folder)
        }
        return entries
    }

    /// Places a top-level group among the loose tabs, before or after `tabID` (or as the first entry with nil).
    func placeFolderAmongTabs(_ id: String, relativeTo tabID: String?, after: Bool) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        let loose = looseTabs.map(\.id)
        var anchor = ""
        if let tabID, let position = loose.firstIndex(of: tabID) {
            anchor = after ? tabID : position > 0 ? loose[position - 1] : ""
        }
        var folder = folders.remove(at: index)
        folder.parentID = nil
        folder.afterTabID = anchor
        // Behind any group already at that place, so a dropped group lands where the line showed.
        folders.append(folder)
        scheduleSave()
    }

    /// Back to the block above the tabs, last there.
    func placeFolderInBlock(_ id: String) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        var folder = folders.remove(at: index)
        folder.parentID = nil
        folder.afterTabID = nil
        folders.append(folder)
        scheduleSave()
    }

    /// A loose tab is leaving its place (closing, moving into a group, pinned, reordered): the groups after it stay where
    /// they are, after the loose tab before it.
    func keepGroupsInPlace(leaving tabID: String) {
        guard folders.contains(where: { $0.afterTabID == tabID }) else { return }
        let loose = looseTabs.map(\.id)
        guard let position = loose.firstIndex(of: tabID) else { return }
        let previous = position > 0 ? loose[position - 1] : ""
        for index in folders.indices where folders[index].afterTabID == tabID { folders[index].afterTabID = previous }
    }

    /// Top-level groups listed as groups in the sidebar, the rail and the tab row: not the hidden ones (they come back
    /// from the Tab Groups button).
    var listedFolders: [TabFolder] { childFolders(of: nil).filter { $0.isClosed != true } }

    /// In the Sidebar layout the tab sits in a group above the New Tab line (or a group inside one): that is pinned, like
    /// a tab there, so closing it keeps it, unloaded.
    func isInPinnedFolder(_ tab: TabItem) -> Bool {
        guard !usesTabsLayout else { return false }
        var next = tab.folderID, steps = 0
        while let id = next, steps < 16, let folder = folders.first(where: { $0.id == id }) {
            if folder.parentID == nil { return folder.afterTabID == nil }
            next = folder.parentID; steps += 1
        }
        return false
    }

    /// Removes a group and the groups inside it, leaving their tabs to the caller to close (`deleteGroup`).
    func deleteFolderTree(_ id: String) {
        let ids = folderSubtreeIDs(id)
        for tab in tabs where tab.folderID.map(ids.contains) == true { tab.folderID = nil }
        folders.removeAll { ids.contains($0.id) }
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

    /// Moves a group inside another (nil: the top level), as its last group. Refuses a move into itself or its own
    /// groups.
    func moveFolder(_ id: String, into parentID: String?) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        if let parentID {
            guard !folderSubtreeIDs(id).contains(parentID),
                  let parent = folders.firstIndex(where: { $0.id == parentID && $0.spaceID == folders[index].spaceID })
            else { return }
            folders[parent].isOpen = true
        }
        var folder = folders.remove(at: index)
        folder.parentID = parentID
        if parentID != nil { folder.afterTabID = nil }
        folders.append(folder)
        scheduleSave()
    }

    /// Whether a dragged group can go before, after or into `targetID`: same Space, and never into its own subtree.
    func canPlaceFolder(_ id: String, relativeTo targetID: String) -> Bool {
        guard id != targetID, let moving = folders.first(where: { $0.id == id }),
              let target = folders.first(where: { $0.id == targetID }) else { return false }
        return moving.spaceID == target.spaceID && !folderSubtreeIDs(id).contains(targetID)
    }

    /// Puts a group right before or after another, beside it (the target's parent becomes its parent).
    func placeFolder(_ id: String, relativeTo targetID: String, after: Bool) {
        guard canPlaceFolder(id, relativeTo: targetID), let from = folders.firstIndex(where: { $0.id == id }) else { return }
        var folder = folders.remove(at: from)
        guard let target = folders.firstIndex(where: { $0.id == targetID }) else { folders.insert(folder, at: from); return }
        folder.parentID = folders[target].parentID
        // Beside a group among the tabs, it joins it there; beside one in the block, the block.
        folder.afterTabID = folders[target].parentID == nil ? folders[target].afterTabID : nil
        folders.insert(folder, at: after ? target + 1 : target)
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

    /// Hides a group: it stays saved with its tabs (and the groups inside it), but its pages unload and it leaves the
    /// tab row until it is shown again (the hidden-groups button, the icon sidebar, Tab ▸ Show Hidden Group). Separate
    /// from collapsing. Returns the unloaded tabs, so the window can put their pages to sleep.
    @discardableResult
    func hideFolder(_ id: String) -> [String] {
        guard !isFrozen, let index = folders.firstIndex(where: { $0.id == id }) else { return [] }
        let members = tabs(inSubtree: folders[index])
        let ids = Set(members.map(\.id))
        if let active = activeTab, ids.contains(active.id) {
            if let next = navigationOrder.first(where: { !ids.contains($0.id) && !$0.isHibernating && !isInClosedFolder($0) })?.id {
                select(next)
            } else {
                activeTabID = nil
            }
        }
        removeFromSplits(ids)
        for member in members { member.isHibernating = true }
        folders[index].isClosed = true
        scheduleSave()
        return members.map(\.id)
    }

    /// The tab sits in a hidden group, or in a group inside one.
    func isInClosedFolder(_ tab: TabItem) -> Bool {
        var next = tab.folderID, steps = 0
        while let id = next, steps < 16, let folder = folders.first(where: { $0.id == id }) {
            if folder.isClosed == true { return true }
            next = folder.parentID; steps += 1
        }
        return false
    }

    /// Reopens a closed group, expanded, and selects its first tab.
    /// Shows a hidden group again, collapsed (like a group just added back); opened when one of its tabs was chosen
    /// (`expanding`), so that tab is on screen.
    func reopenFolder(_ id: String, selecting: Bool = true, expanding: Bool = false) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[index].isClosed = nil
        folders[index].isOpen = expanding
        if selecting, let first = tabs(inSubtree: folders[index]).first { select(first.id) }
        scheduleSave()
    }

    /// Selecting a tab of a closed group (from history, the omnibox or the sidebar) reopens the group, and any hidden
    /// group around it.
    func reopenFolderIfClosed(containing tabID: String) {
        var next = tab(tabID)?.folderID, steps = 0
        while let id = next, steps < 16, let folder = folders.first(where: { $0.id == id }) {
            if folder.isClosed == true { reopenFolder(id, selecting: false, expanding: true) }
            next = folder.parentID; steps += 1
        }
    }
}

// MARK: - Essentials
extension BrowserState {
    var showsPinnedGrid: Bool { browserPreferences.showPinnedGrid ?? true }
    var presentsSidebarPinGrid: Bool { showsPinnedGrid }
    /// Essentials columns: three or four (an older profile's other counts read as the nearest).
    var essentialsColumns: Int { (browserPreferences.pinnedGridColumns ?? 3) >= 4 ? 4 : 3 }
    var sidebarGridPinnedTabs: [TabItem] {
        pinnedTabs.filter { !$0.pinAsRow && splitGroup(of: $0.id) == nil }
    }

    /// Address-bar navigation preserves live pins. Page links remain native navigation.
    func addressNeedsNewTab(for url: String) -> Bool {
        guard let active = activeTab, active.pinned else { return false }
        return Self.pageKey(active.url) != Self.pageKey(url)
    }
}
