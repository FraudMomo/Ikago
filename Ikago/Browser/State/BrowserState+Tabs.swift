import Foundation

// MARK: - TabLifecycle
/// Selection history and page release operations for tabs.
extension BrowserState {
    /// Selects a tab, switching to its Space first if needed.
    func select(_ id: String) {
        guard let tab = tab(id) else { return }
        if let previous = activeTabID, previous != id, self.tab(previous)?.spaceID == tab.spaceID {
            rememberSelection(previous, in: tab.spaceID)
        }
        if tab.spaceID != activeSpaceID { enterSpace(tab.spaceID) }
        // Like Chrome, choosing any other tab ends every "back to the opener on close" link but the chosen tab's own.
        for other in tabs where other.openerID != nil && other.id != id { other.openerID = nil }
        reopenFolderIfClosed(containing: id)
        activeTabID = id
        rememberSelection(id, in: tab.spaceID)
        scheduleSave()
    }

    /// `detaching`: the tab is moving to another window (`detachTab`), so it is neither kept as a closed pin nor listed
    /// under recently closed.
    func closeTab(_ id: String, removingPin: Bool = false, detaching: Bool = false) {
        guard !isFrozen, let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = tabs[index]
        if tab.pinned && !removingPin && !detaching {
            removeFromSplits([id])
            if activeTabID == id { selectCloseFallback(for: tab, excluding: [id]) }
            tab.isHibernating = true
            scheduleSave()
            return
        }
        let order = tab.spaceID == activeSpaceID ? navigationOrder : []
        let position = order.firstIndex { $0.id == id } ?? 0
        let neighbours = order.filter { $0.id != id }
        let partner = splitGroup(of: id)?.first { $0 != id }
        let previous = tabs[..<index].last { $0.spaceID == tab.spaceID }?.id
        tabs.remove(at: index)
        if !detaching, AddressResolver.isPageURL(tab.url) || ExtensionURL.isExtension(tab.url) || Self.isReopenableInternalPage(tab.url),
           !isUntouchedNewTab(tab) {
            var saved = tab.saved
            saved.after = previous
            closed = Array(([saved] + closed).prefix(Session.maxClosed))
        }
        removeFromSplits([id])
        if activeTabID == id {
            // Chrome's choice: back to the tab that opened this one (if the person stayed on it), then its split partner,
            // then the tab to the right, then the one to the left.
            let opener = tab.openerID.flatMap { self.tab($0) }.flatMap { $0.spaceID == tab.spaceID ? $0.id : nil }
            let fallback = opener ?? partner
                ?? (neighbours.isEmpty ? nil : neighbours[min(position, neighbours.count - 1)].id)
            if let fallback { select(fallback) } else { activeTabID = nil }
        }
        scheduleSave()
    }

    /// Marks a tab unloaded and returns its ID when its live page can safely be released.
    @discardableResult
    func unloadTab(_ id: String) -> String? {
        guard !isFrozen, let tab = tab(id) else { return nil }
        if activeTabID == id {
            if let next = recentFallback(for: tab, excluding: [id])
                ?? navigationOrder.first(where: { $0.id != id && !$0.isHibernating })?.id { select(next) }
            else { activeTabID = nil }
        }
        removeFromSplits([id])
        tab.isHibernating = true
        scheduleSave()
        return id
    }

    /// Marks every page in a group unloaded; returns the IDs the window should hibernate.
    @discardableResult
    func unloadFolder(_ id: String) -> [String] {
        guard !isFrozen, let folder = folders.first(where: { $0.id == id }) else { return [] }
        let members = tabs(in: folder)
        let ids = Set(members.map(\.id))
        if let active = activeTab, ids.contains(active.id) {
            if let next = navigationOrder.first(where: { !ids.contains($0.id) && !$0.isHibernating })?.id { select(next) }
            else { activeTabID = nil }
        }
        removeFromSplits(ids)
        for member in members { member.isHibernating = true }
        scheduleSave()
        return members.map(\.id)
    }

    private func rememberSelection(_ id: String, in spaceID: UUID) {
        var recent = recentTabSelections[spaceID, default: []]
        recent.removeAll { $0 == id }
        recent.insert(id, at: 0)
        recentTabSelections[spaceID] = Array(recent.prefix(64))
    }

    private func recentFallback(for tab: TabItem, excluding ids: Set<String>) -> String? {
        recentTabSelections[tab.spaceID, default: []].first { candidate in
            !ids.contains(candidate) && self.tab(candidate)?.spaceID == tab.spaceID
                && self.tab(candidate)?.isHibernating == false
                && !(self.tab(candidate)?.folderID.flatMap { folder in folders.first { $0.id == folder }?.isClosed } ?? false)
        }
    }

    private func selectCloseFallback(for tab: TabItem, excluding ids: Set<String>) {
        if let fallback = recentFallback(for: tab, excluding: ids) { select(fallback); return }
        if let fallback = navigationOrder.first(where: { !ids.contains($0.id) && !$0.isHibernating }) { select(fallback.id) }
        else { activeTabID = nil }
    }
}

// MARK: - TabPlacement
enum NewTabPosition: String, CaseIterable, Identifiable {
    case top, bottom
    var id: String { rawValue }
    var title: String { self == .top ? "Newest on top" : "Newest on bottom" }
}

enum LinkTabPosition: String, CaseIterable, Identifiable {
    case beforeCurrent, afterCurrent, newTabPosition
    var id: String { rawValue }
    var title: String {
        switch self {
        case .beforeCurrent: "Before current tab"
        case .afterCurrent: "After current tab"
        case .newTabPosition: "Same as new tabs"
        }
    }
}

extension BrowserState {
    var newTabPosition: NewTabPosition {
        get { browserPreferences.newTabPosition.flatMap(NewTabPosition.init(rawValue:)) ?? .bottom }
        set { browserPreferences.newTabPosition = newValue.rawValue }
    }
    /// Tabs across the top always open on the right, after the others; the setting orders the sidebar's list.
    var effectiveNewTabPosition: NewTabPosition { usesTabsLayout ? .bottom : newTabPosition }
    var effectiveLinkTabPosition: LinkTabPosition { linkTabPosition }

    var linkTabPosition: LinkTabPosition {
        get { browserPreferences.linkTabPosition.flatMap(LinkTabPosition.init(rawValue:)) ?? .afterCurrent }
        set { browserPreferences.linkTabPosition = newValue.rawValue }
    }

    /// One insertion policy for links, Cmd-click, middle-click and WebKit popup adoption.
    /// Keep the opener's Space/profile even when it is no longer the foreground Space.
    @discardableResult
    func newTabFromLink(url: String, opener: TabItem, select: Bool) -> TabItem? {
        switch effectiveLinkTabPosition {
        case .newTabPosition:
            return remembering(opener, newTab(url: url, select: select, in: opener.spaceID))
        case .beforeCurrent, .afterCurrent:
            if opener.pinned {
                // Tabs across the top: a pin isn't in the row, so its links open where new tabs do, on the right.
                if usesTabsLayout { return remembering(opener, newTab(url: url, select: select, in: opener.spaceID)) }
                // Unpinned links cannot enter the pinned grid; place them at the start of loose tabs.
                let first = tabs.first { $0.spaceID == opener.spaceID && !$0.pinned && $0.folderID == nil }
                return remembering(opener, newTab(url: url, select: select, before: first?.id, in: opener.spaceID))
            }
            let result = newTab(url: url, select: select,
                                after: effectiveLinkTabPosition == .afterCurrent ? opener.id : nil,
                                before: effectiveLinkTabPosition == .beforeCurrent ? opener.id : nil,
                                in: opener.spaceID, folderID: opener.folderID)
            if select, let folder = opener.folderID, let index = folders.firstIndex(where: { $0.id == folder }) {
                folders[index].isOpen = true
            }
            return remembering(opener, result)
        }
    }

    private func remembering(_ opener: TabItem, _ tab: TabItem?) -> TabItem? {
        tab?.openerID = opener.id
        return tab
    }
}

// MARK: - Reordering
extension BrowserState {
    func canReorderTab(_ id: String, relativeTo targetID: String) -> Bool {
        guard id != targetID, let moving = tab(id), let target = tab(targetID),
              moving.spaceID == activeSpaceID, target.spaceID == activeSpaceID else { return false }
        return splitGroup(of: id)?.contains(targetID) != true
    }

    /// Reorder at a visible item's boundary. Split groups move together and stay intact.
    @discardableResult
    func reorderTab(_ id: String, relativeTo targetID: String, after: Bool) -> Bool {
        guard canReorderTab(id, relativeTo: targetID), let target = tab(targetID) else { return false }
        let moving = splitGroup(of: id) ?? [id]
        let targetGroup = splitGroup(of: targetID) ?? [targetID]
        let peers = tabs.filter {
            $0.spaceID == target.spaceID && $0.pinned == target.pinned && $0.folderID == target.folderID && !moving.contains($0.id)
        }
        let boundary: String?
        if after, let last = peers.lastIndex(where: { targetGroup.contains($0.id) }) {
            boundary = peers.indices.contains(last + 1) ? peers[last + 1].id : nil
        } else {
            boundary = peers.first { targetGroup.contains($0.id) }?.id
        }
        for member in moving {
            move(member, before: boundary, pinned: target.pinned, folderID: target.folderID)
            if let tab = tab(member), tab.pinned {
                tab.pinAsRow = target.pinAsRow
                tab.pinAfterFolderID = target.pinAfterFolderID
            }
        }
        scheduleSave()
        return true
    }

    @discardableResult
    func moveTabToListEnd(_ id: String) -> Bool {
        guard let moving = tab(id), moving.spaceID == activeSpaceID else { return false }
        for member in splitGroup(of: id) ?? [id] {
            move(member, before: nil, pinned: false)
        }
        scheduleSave()
        return true
    }
}

extension BrowserState {
    func movePin(_ id: String, intoGrid: Bool, afterFolderID: String? = nil) {
        guard tab(id)?.spaceID == activeSpaceID else { return }
        let members = splitGroup(of: id) ?? [id]
        for member in members {
            self.tab(member)?.pinAsRow = !intoGrid || members.count > 1
            self.tab(member)?.pinAfterFolderID = intoGrid ? nil : afterFolderID
            move(member, before: nil, pinned: true)
        }
    }
}

extension BrowserState {
    var orderedSidebarTabs: [TabItem] {
        let rows = pinnedTabs.filter { !presentsSidebarPinGrid || $0.pinAsRow || splitGroup(of: $0.id) != nil }
        let folderIDs = Set(spaceFolders.map(\.id))
        let anchors = Dictionary(grouping: rows) { tab in tab.pinAfterFolderID.flatMap { folderIDs.contains($0) ? $0 : nil } ?? "" }
        let grid = presentsSidebarPinGrid ? sidebarGridPinnedTabs : []
        return grid + (anchors[""] ?? []) + orderedSpaceFolders.flatMap { tabs(in: $0) + (anchors[$0.id] ?? []) } + looseTabs
    }
}

// MARK: - Untouched new tabs
extension BrowserState {
    /// A tab still on the page it opened with as a new tab (an extension's new-tab page such as Momentum's, or the
    /// homepage when new tabs open it), with nowhere to go back to. Like Chrome's New Tab page, closing one leaves
    /// nothing for ⌘⇧T, which goes straight to the last real page. Blank tabs are never recorded at all.
    func isUntouchedNewTab(_ tab: TabItem) -> Bool {
        guard !tab.canGoBack, tab.history?.back?.isEmpty ?? true else { return false }
        if ExtensionURL.isExtension(tab.url), let page = URL(string: tab.url) {
            return NewTabProviders.current.contains { provider in
                provider.url.host?.lowercased() == page.host?.lowercased() && provider.url.path == page.path
            }
        }
        if newTabMode == .homepage, let home = try? AddressResolver.resolve(homepage, engine: searchEngine) {
            return Self.pageKey(tab.url) == Self.pageKey(home)
        }
        return false
    }
}
