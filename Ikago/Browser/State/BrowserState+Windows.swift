import Foundation

/// Several regular windows, as in Chrome: each window's state has its own tabs, groups and split views; Spaces,
/// settings, history and bookmarks are one set, copied between the windows' states whenever any of them changes it
/// (`shareChanges`). The first window's state (`primary`) saves the session with the others in `Session.windows`.
extension BrowserState {
    /// A window after the first: `primary`'s settings and Spaces, and the saved window's tabs (or none, for a new one).
    convenience init(windowOf primary: BrowserState, session window: WindowSession? = nil) {
        // A store nothing is ever written to: every save goes to the primary.
        self.init(store: SessionStore(directory: FileManager.default.temporaryDirectory.appending(path: "IkagoWindow-\(UUID())")))
        self.primary = primary
        var session = primary.snapshot()
        session.windows = nil
        session.tabs = window?.tabs ?? []
        session.active = window?.active
        session.closed = window?.closed ?? []
        session.splits = window?.splits
        session.splitLayout = window?.splitLayout ?? session.splitLayout
        session.activeSpace = window?.activeSpace ?? primary.activeSpaceID
        session.lastActiveTab = window?.lastActiveTab
        session.folders = window?.folders
        session.sidebar = window?.sidebar ?? primary.sidebarVisible
        apply(session)
        systemIsDark = primary.systemIsDark
        windowFrame = window?.screenFrame
        saveTask?.cancel()
    }

    /// This window's part of the session.
    func windowSnapshot() -> WindowSession {
        let session = snapshot()
        var window = WindowSession(tabs: session.tabs, active: session.active, closed: closed.isEmpty ? nil : closed)
        window.splits = session.splits
        window.splitLayout = session.splitLayout
        window.activeSpace = session.activeSpace
        window.lastActiveTab = session.lastActiveTab
        window.folders = session.folders
        window.sidebar = sidebarVisible
        window.frame = windowFrame.map { [$0.minX, $0.minY, $0.width, $0.height] }
        return window
    }

    /// Every regular window's state: the primary first.
    var windowGroup: [BrowserState] {
        let root = primary ?? self
        return [root] + root.windowStates
    }

    /// Reads everything the windows share (for observation), and copies it to the other windows when it changes.
    func readShared() {
        _ = (history, bookmarks, bookmarkFolders, browserPreferences, colorMode, sidebarWidth, useGlass, frameInset, sidebarGap,
             searchShowsHistory, addressStyle, developerTools, chromeLayout, newTabMode, focusAddressBarOnNewTab, homepage,
             newTabExtensionID, searchEngine, spaces)
    }

    func shareChanges() {
        guard !isPrivate, !isFrozen else { return }
        for other in windowGroup where other !== self && !other.isFrozen { other.takeShared(from: self) }
    }

    /// Takes `other`'s shared settings; each field only when it differs, so the copy settles instead of echoing back.
    private func takeShared(from other: BrowserState) {
        func take<T: Equatable>(_ path: ReferenceWritableKeyPath<BrowserState, T>) {
            if self[keyPath: path] != other[keyPath: path] { self[keyPath: path] = other[keyPath: path] }
        }
        take(\.history); take(\.bookmarks); take(\.bookmarkFolders); take(\.browserPreferences); take(\.colorMode)
        take(\.sidebarWidth); take(\.useGlass); take(\.frameInset); take(\.sidebarGap); take(\.searchShowsHistory)
        take(\.addressStyle); take(\.developerTools); take(\.chromeLayout); take(\.newTabMode); take(\.focusAddressBarOnNewTab)
        take(\.homepage); take(\.newTabExtensionID); take(\.searchEngine); take(\.spaces)
        // A Space deleted in another window: its tabs here move to the first Space instead of vanishing.
        let known = Set(spaces.map(\.id))
        for tab in tabs where !known.contains(tab.spaceID) { tab.spaceID = spaces[0].id }
        folders = folders.filter { known.contains($0.spaceID) }
        if !known.contains(activeSpaceID) { activeSpaceID = spaces[0].id }
    }

    /// Removes a tab that is moving to another window, choosing the next tab as closing it would. Returns the tab.
    func detachTab(_ id: String) -> TabItem? {
        guard !isFrozen, let tab = tab(id) else { return nil }
        closeTab(id, detaching: true)
        return tab
    }

    /// Takes in a tab from another window, as a loose tab (groups belong to their window), and selects it. With
    /// `space` (a drop on this window's list), it joins that Space when both keep their website data in the same store,
    /// so its live page stays signed in; otherwise it keeps its own Space and the window shows that.
    func adoptTab(_ tab: TabItem, space: UUID? = nil) {
        guard !isFrozen, self.tab(tab.id) == nil else { return }
        tab.folderID = nil
        tab.pinAfterFolderID = nil
        tab.openerID = nil
        let profile = { (id: UUID) in self.spaces.first { $0.id == id }?.profileID }
        if let space, profile(space) != nil, profile(space) == profile(tab.spaceID) { tab.spaceID = space }
        if !spaces.contains(where: { $0.id == tab.spaceID }) { tab.spaceID = activeSpaceID }
        tabs.append(tab)
        select(tab.id)
    }

    /// Takes over another window's tabs, groups and split views; this window's own tabs go to recently closed.
    func takeWindow(from other: BrowserState) {
        guard !isFrozen else { return }
        let mine = tabs.filter { AddressResolver.isPageURL($0.url) || Self.isReopenableInternalPage($0.url) }.map(\.saved)
        closed = Array((other.closed + mine + closed).prefix(Session.maxClosed))
        folders = other.folders
        tabs = other.tabs
        splits = other.splits
        splitLayout = other.splitLayout
        lastActiveTab = other.lastActiveTab
        activeSpaceID = other.activeSpaceID
        activeTabID = other.activeTabID
        sidebarVisible = other.sidebarVisible
        scheduleSave()
    }
}
