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

    /// Creates a folder in the active Space, optionally moving `tabID` into it.
    @discardableResult
    func createFolder(named name: String, with tabID: String? = nil) -> TabFolder {
        let folder = TabFolder(name: name.isEmpty ? "New Group" : name, spaceID: activeSpaceID)
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

    /// Deletes the folder; its tabs stay open as loose tabs.
    func deleteFolder(_ id: String) {
        for tab in tabs where tab.folderID == id { tab.folderID = nil }
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
        if let folderID, let index = folders.firstIndex(where: { $0.id == folderID }) { folders[index].isOpen = true }
    }
}
