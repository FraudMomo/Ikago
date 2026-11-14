import Foundation

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
