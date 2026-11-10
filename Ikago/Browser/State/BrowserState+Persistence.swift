import Foundation

extension BrowserState {
    // MARK: Persistence

    /// Coalesces changes for a second, then saves off the main thread if anything differs from the last save.
    func scheduleSave() {
        guard !isFrozen, !isPrivate else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self, !self.isFrozen else { return }
            let session = self.snapshot()
            guard session != self.lastSavedSession else { return }
            self.lastSavedSession = session
            // Not saved: forget it, so the next change saves everything.
            self.store.saveInBackground(session) { [weak self] in self?.lastSavedSession = nil }
        }
    }

    /// Final save, then ignore every later mutation (quit / window close).
    func freezeForShutdown() {
        guard !isFrozen else { return }
        saveNow()
        isFrozen = true
    }

    /// Saves synchronously, after any background saves still queued, and always writes (so the backup catches up too).
    func saveNow() {
        guard !isFrozen, !isPrivate else { return }
        saveTask?.cancel()
        let session = snapshot()
        lastSavedSession = store.saveAndWait(session) ? session : nil
    }

    func snapshot() -> Session {
        var session = Session()
        session.tabs = tabs.filter { AddressResolver.isPageURL($0.url) || InternalPage(url: $0.url) != nil || ExtensionURL.isExtension($0.url) }.map(\.saved)
        session.active = session.tabs.contains { $0.id == activeTabID } ? activeTabID : session.tabs.first { $0.unloaded != true }?.id
        session.closed = closed
        session.history = history
        session.bookmarks = bookmarks
        session.bookmarkFolders = bookmarkFolders
        session.browser = browserPreferences
        session.theme = SpaceColors.presets.first { $0.colors == activeSpace.resolvedColors }?.name.lowercased() ?? "mist"
        session.layout = tabLayout.rawValue
        session.colorMode = colorMode.rawValue
        session.sidebarWidth = sidebarWidth
        session.ui = UISettings(glass: useGlass, inset: frameInset, history: searchShowsHistory, devTools: developerTools,
                                gap: sidebarGap, address: addressStyle.rawValue, tintBar: tintBarWithPage, barHeight: barHeight, barBorder: barBorder, barGap: barGap, barRounded: barRounded)
        session.chrome = chromeLayout
        session.newTab = NewTabSettings(mode: newTabMode.rawValue, homepage: homepage, extensionID: newTabExtensionID, focusAddressBar: focusAddressBarOnNewTab)
        session.search = searchEngine.rawValue
        session.sidebar = sidebarVisible
        let savedIDs = Set(session.tabs.map(\.id))
        session.splits = splits.map { $0.filter(savedIDs.contains) }.filter { $0.count >= 2 }
        session.splitLayout = splitLayout.rawValue
        session.spaces = spaces
        session.activeSpace = activeSpaceID
        var remembered = Dictionary(uniqueKeysWithValues: lastActiveTab.map { ($0.key.uuidString, $0.value) })
        if let activeTabID { remembered[activeSpaceID.uuidString] = activeTabID }
        session.lastActiveTab = remembered.filter { savedIDs.contains($0.value) }
        session.folders = folders
        return session
    }

    func restore() {
        switch store.load() {
        case .fresh:
            if Self.isRealProfile(store) {
                applyNewProfileDefaults()
                pendingWelcome = true
            }
            return
        case .unreadable(let stamp):
            restoreWarning = "Your saved session could not be read. The original files were kept as session*.unreadable-\(stamp).json beside the session."
        case .loaded(let s):
            apply(s)
        }
        saveTask?.cancel()  // restoring is not a change
    }

    /// Takes on a saved session (from disk, or a copy for a private window).
    func apply(_ s: Session) {
        spaces = (s.spaces ?? []).isEmpty ? [.defaultSpace] : s.spaces!
        folders = s.folders ?? []
        let known = Set(spaces.map(\.id)), folderIDs = Set(folders.map(\.id))
        tabs = s.tabs.map { saved in
            let space = saved.space.flatMap(UUID.init(uuidString:)).flatMap { known.contains($0) ? $0 : nil }
            let tab = TabItem(id: saved.id, url: saved.url, title: saved.title, pinned: saved.pinned,
                           spaceID: space ?? spaces[0].id,
                           folderID: saved.folder.flatMap { folderIDs.contains($0) ? $0 : nil })
            tab.faviconURL = saved.favicon.flatMap(URL.init(string:))
            tab.isHibernating = saved.unloaded ?? false
            return tab
        }
        tabs = tabs.filter(\.pinned) + tabs.filter { !$0.pinned }
        activeTabID = s.active ?? tabs.first { !$0.isHibernating }?.id
        activeSpaceID = tabs.first { $0.id == activeTabID }?.spaceID ?? s.activeSpace.flatMap { known.contains($0) ? $0 : nil } ?? spaces[0].id
        lastActiveTab = Dictionary(uniqueKeysWithValues: (s.lastActiveTab ?? [:]).compactMap { key, value in
            UUID(uuidString: key).map { ($0, value) }
        })
        closed = s.closed
        history = s.history
        bookmarks = s.bookmarks ?? []
        bookmarkFolders = s.bookmarkFolders ?? []
        browserPreferences = (s.browser ?? BrowserPreferences()).validated
        // The retired Chrome layout had top tabs, so its sessions continue on the other top-tab layout.
        tabLayout = s.layout == "chrome" ? .horizontal : s.layout.flatMap(TabLayout.init(rawValue:)) ?? .vertical
        colorMode = s.colorMode.flatMap(ColorMode.init(rawValue:)) ?? .system
        sidebarWidth = min(420, max(200, s.sidebarWidth ?? Self.defaultSidebarWidth))
        useGlass = s.ui?.glass ?? true
        frameInset = min(24, max(0, s.ui?.inset ?? Self.defaultFrameInset))
        sidebarGap = min(24, max(0, s.ui?.gap ?? Self.defaultSidebarGap))
        addressStyle = s.ui?.address.flatMap(AddressStyle.init(rawValue:)) ?? .integrated
        tintBarWithPage = s.ui?.tintBar ?? true
        barHeight = min(56, max(22, s.ui?.barHeight ?? Self.defaultBarHeight))
        barBorder = min(3, max(0, s.ui?.barBorder ?? 0))
        barGap = min(24, max(0, s.ui?.barGap ?? Self.defaultBarGap))
        barRounded = s.ui?.barRounded ?? false
        searchShowsHistory = s.ui?.history ?? true
        developerTools = s.ui?.devTools ?? true
        chromeLayout = s.chrome ?? ChromeLayout()
        newTabMode = s.newTab.flatMap { NewTabMode(rawValue: $0.mode) } ?? .commandBar
        homepage = s.newTab?.homepage ?? ""
        newTabExtensionID = s.newTab?.extensionID
        focusAddressBarOnNewTab = s.newTab?.focusAddressBar ?? false
        // Older sessions: a global theme becomes every Space's color.
        for i in spaces.indices {
            let colors = spaces[i].colors ?? SpaceColors.legacy(spaces[i].theme) ?? SpaceColors.legacy(s.theme) ?? .standard
            spaces[i].colors = SpaceColors.migrated(colors)
        }
        searchEngine = SearchEngine(rawValue: s.search) ?? .duckduckgo
        sidebarVisible = s.sidebar
        let tabIDs = Set(tabs.map(\.id))
        splits = (s.splits ?? s.split.map { [$0] } ?? []).map { $0.filter(tabIDs.contains) }.filter { $0.count >= 2 }
        splitLayout = s.splitLayout.flatMap(SplitLayout.init(rawValue:)) ?? ((s.splitVertical ?? true) ? .columns : .rows)
        saveTask?.cancel()
    }
}
