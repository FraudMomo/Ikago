import Foundation

/// Selection history and page release operations for tabs.
extension BrowserState {
    /// Selects a tab, switching to its Space first if needed.
    func select(_ id: String) {
        guard let tab = tab(id) else { return }
        if let previous = activeTabID, previous != id, self.tab(previous)?.spaceID == tab.spaceID {
            rememberSelection(previous, in: tab.spaceID)
        }
        if tab.spaceID != activeSpaceID { enterSpace(tab.spaceID) }
        reopenFolderIfClosed(containing: id)
        activeTabID = id
        rememberSelection(id, in: tab.spaceID)
        scheduleSave()
    }

    func closeTab(_ id: String, removingPin: Bool = false) {
        guard !isFrozen, let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = tabs[index]
        if tab.pinned && !removingPin {
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
        tabs.remove(at: index)
        if AddressResolver.isPageURL(tab.url) || ExtensionURL.isExtension(tab.url) || Self.isReopenableInternalPage(tab.url) {
            closed = Array(([tab.saved] + closed).prefix(Session.maxClosed))
        }
        removeFromSplits([id])
        if activeTabID == id {
            let fallback = recentFallback(for: tab, excluding: [id]) ?? partner
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
