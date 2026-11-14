import Foundation

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
