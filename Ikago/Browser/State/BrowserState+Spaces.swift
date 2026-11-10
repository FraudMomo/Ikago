import Foundation

/// Spaces: each has its own tabs, folders, colors and remembered active tab.
extension BrowserState {
    /// Shows `id`'s tabs and selects the tab it had last.
    func switchSpace(_ id: UUID) {
        guard id != activeSpaceID, spaces.contains(where: { $0.id == id }) else { return }
        enterSpace(id)
        let remembered = lastActiveTab[id].flatMap(tab)
        activeTabID = remembered?.spaceID == id ? remembered?.id : sidebarOrder.first?.id
        scheduleSave()
    }

    /// Switches the active Space without choosing a tab (callers select one).
    func enterSpace(_ id: UUID) {
        if let activeTabID { lastActiveTab[activeSpaceID] = activeTabID }
        activeSpaceID = id
    }

    func selectAdjacentSpace(_ offset: Int) {
        guard let index = spaces.firstIndex(where: { $0.id == activeSpaceID }), spaces.count > 1 else { return }
        switchSpace(spaces[(index + offset + spaces.count) % spaces.count].id)
    }

    @discardableResult
    func createSpace(name: String, symbol: String, isolated: Bool) -> SpaceProfile {
        var space = SpaceProfile(id: UUID(), name: name, symbol: symbol, isolated: isolated)
        // A new Space gets the next preset color so Spaces are easy to tell apart.
        let used = Set(spaces.map(\.resolvedColors))
        space.colors = SpaceColors.presets.first { !used.contains($0.colors) }?.colors ?? .standard
        spaces.append(space)
        switchSpace(space.id)
        return space
    }

    func renameSpace(_ id: UUID, to name: String) {
        guard let index = spaces.firstIndex(where: { $0.id == id }), !name.isEmpty else { return }
        spaces[index].name = name
        scheduleSave()
    }

    /// Removes the Space with its tabs and folders. The last Space can't be deleted.
    func deleteSpace(_ id: UUID) {
        guard spaces.count > 1, spaces.contains(where: { $0.id == id }) else { return }
        if activeSpaceID == id, let other = spaces.first(where: { $0.id != id }) { switchSpace(other.id) }
        let removed = Set(tabs.filter { $0.spaceID == id }.map(\.id))
        tabs.removeAll { removed.contains($0.id) }
        removeFromSplits(removed)
        folders.removeAll { $0.spaceID == id }
        lastActiveTab[id] = nil
        spaces.removeAll { $0.id == id }
        scheduleSave()
    }

    /// Moves a tab to another Space, out of any folder. Between Spaces that share storage
    /// the page moves as is; into or out of an isolated Space it reopens with that Space's logins.
    func moveTab(_ id: String, toSpace spaceID: UUID) {
        guard let tab = tab(id), tab.spaceID != spaceID,
              let target = spaces.first(where: { $0.id == spaceID }) else { return }
        let sameStorage = spaces.first { $0.id == tab.spaceID }?.profileID == target.profileID
        guard sameStorage else {
            closeTab(id, removingPin: true)
            if closed.first?.url == tab.url { closed.removeFirst() }
            tabs.append(TabItem(url: tab.url, title: tab.title, pinned: tab.pinned, spaceID: spaceID))
            tabs = tabs.filter(\.pinned) + tabs.filter { !$0.pinned }
            scheduleSave()
            return
        }
        if activeTabID == id {
            let order = sidebarOrder
            let position = order.firstIndex { $0.id == id } ?? 0
            let rest = order.filter { $0.id != id }
            activeTabID = rest.isEmpty ? nil : rest[min(position, rest.count - 1)].id
        }
        removeFromSplits([id])
        tab.spaceID = spaceID
        tab.folderID = nil
        scheduleSave()
    }

    func setColors(_ colors: SpaceColors, for id: UUID) {
        guard let index = spaces.firstIndex(where: { $0.id == id }) else { return }
        spaces[index].colors = colors
        scheduleSave()
    }
}
