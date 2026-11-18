import Foundation

// MARK: - Spaces
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

    /// Moves a tab to another Space, out of any folder (or into `folderID`, a group already moved there). Between
    /// Spaces that share storage the page moves as is; into or out of an isolated Space it reopens with that Space's
    /// logins.
    func moveTab(_ id: String, toSpace spaceID: UUID, folderID: String? = nil) {
        guard let tab = tab(id), tab.spaceID != spaceID,
              let target = spaces.first(where: { $0.id == spaceID }) else { return }
        let sameStorage = spaces.first { $0.id == tab.spaceID }?.profileID == target.profileID
        guard sameStorage else {
            closeTab(id, removingPin: true)
            if closed.first?.url == tab.url { closed.removeFirst() }
            tabs.append(TabItem(url: tab.url, title: tab.title, pinned: tab.pinned, spaceID: spaceID, folderID: folderID))
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
        tab.folderID = folderID
        tab.pinAfterFolderID = nil
        scheduleSave()
    }

    /// Moves several tabs to another Space, keeping their order.
    func moveTabs(_ ids: [String], toSpace spaceID: UUID) {
        for id in ids { moveTab(id, toSpace: spaceID) }
    }

    /// Moves a group to another Space with the groups inside it and all their tabs, at the end of that Space's
    /// groups. It arrives at the top level there; its tabs keep their places inside it.
    func moveFolder(_ id: String, toSpace spaceID: UUID) {
        guard let folder = folders.first(where: { $0.id == id }), folder.spaceID != spaceID,
              spaces.contains(where: { $0.id == spaceID }) else { return }
        let subtree = folderSubtreeIDs(id)
        let moving = tabs.filter { $0.spaceID == folder.spaceID && $0.folderID.map(subtree.contains) == true }
            .map { ($0.id, $0.folderID) }
        // Folders first, so the tabs land in groups that already belong to the target Space.
        var moved = folders.filter { subtree.contains($0.id) }
        folders.removeAll { subtree.contains($0.id) }
        for index in moved.indices {
            moved[index].spaceID = spaceID
            if moved[index].id == id { moved[index].parentID = nil }
        }
        folders.append(contentsOf: moved)
        for (tabID, folderID) in moving { moveTab(tabID, toSpace: spaceID, folderID: folderID) }
        // Pins placed after the group in its old Space go back above the groups.
        for tab in tabs where tab.pinAfterFolderID.map(subtree.contains) == true && tab.spaceID != spaceID {
            tab.pinAfterFolderID = nil
        }
        scheduleSave()
    }

    func setColors(_ colors: SpaceColors, for id: UUID) {
        guard let index = spaces.firstIndex(where: { $0.id == id }) else { return }
        spaces[index].colors = colors
        scheduleSave()
    }
}

// MARK: - Defaults
/// How a brand-new profile starts. Saved profiles keep their own choices: these values are written once, when there is
/// no session yet, so changing them never alters an existing profile. Unattended checks keep the built-in defaults.
extension BrowserState {
    /// The engine a new profile starts on. The welcome page (`InternalPage.welcome`) asks before any site loads.
    static let newProfileEngine = BrowserEngine.chromium

    /// The person's own profile, not a check run's disposable one.
    static func isRealProfile(_ store: SessionStore) -> Bool {
        EngineCookieSync.usesRealStores && store.directory == SessionStore.standard.directory
    }

    func applyNewProfileDefaults() {
        sidebarVisible = true
        frameInset = 2
        sidebarGap = 3
        useGlass = false
        addressStyle = .floating
        searchEngine = .google
        groupLabelStyle = .colorPill
        showsGroupTabCounts = false
        tabHighlightStyle = .none
        showsBookmarksBar = false
        browserPreferences.translucentSidebar = true
        browserPreferences.sidebarCompact = nil
        browserPreferences.instantTabSwitching = true
        browserPreferences.showPinnedGrid = true
        browserPreferences.preferredEngine = Self.newProfileEngine
        browserPreferences.chromiumVideoTranslation = false
        browserPreferences.resourcePolicy = .balanced
        chromeLayout.sidebarTop = [.sidebarToggle, .back, .forward]
        chromeLayout.sidebarBottom = [.spaces, .newSpace, .settings]
    }
}
