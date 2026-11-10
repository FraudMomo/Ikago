import Foundation

/// Closed tab groups: a group closed from a top layout leaves the strip
/// (no space taken) but keeps its tabs, unloaded, so it can be reopened from the Tab menu or
/// the new-tab button's menu. Selecting one of its tabs reopens it.
extension BrowserState {
    /// The active Space's closed groups, in sidebar order.
    var closedFolders: [TabFolder] { spaceFolders.filter { $0.isClosed == true } }

    /// The groups a top tab strip shows.
    var stripFolders: [TabFolder] { spaceFolders.filter { $0.isClosed != true } }

    /// Tab order for next/previous tab and close-neighbour selection. Top layouts skip closed groups,
    /// which aren't on screen; the sidebar lists every group, so it keeps `sidebarOrder`.
    var navigationOrder: [TabItem] {
        guard tabLayout.usesTopTabs else { return sidebarOrder }
        let closed = Set(closedFolders.map(\.id))
        return sidebarOrder.filter { $0.folderID.map { !closed.contains($0) } ?? true }
    }

    /// Closes the group and moves selection off it (to the nearest tab outside it, or a new tab).
    /// Returns the tabs to unload; the window hibernates them once they're no longer active.
    @discardableResult
    func closeFolder(_ id: String) -> [String] {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return [] }
        let members = tabs(in: folders[index])
        let order = sidebarOrder
        folders[index].isClosed = true
        let memberIDs = Set(members.map(\.id))
        if let active = activeTab, memberIDs.contains(active.id) || splitGroup(of: active.id).map({ !memberIDs.isDisjoint(with: $0) }) == true {
            let position = order.firstIndex { $0.id == active.id } ?? 0
            let others = navigationOrder
            let after = others.first { candidate in (order.firstIndex { $0.id == candidate.id } ?? 0) > position }
            if let next = after ?? others.last { select(next.id) } else { _ = newTab(url: "about:blank") }
        }
        removeFromSplits(memberIDs)
        // A tab opened just before its group closed must not start loading in the background afterwards.
        for member in members { member.shouldStartInBackground = false }
        scheduleSave()
        return members.map(\.id)
    }

    /// Puts a closed group back in the strip, expanded, and selects its first tab.
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
