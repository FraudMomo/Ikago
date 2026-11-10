import Foundation

/// Split view: any number of groups of 2–4 tabs. Selecting a tab in a group shows the
/// whole group side by side.
extension BrowserState {
    /// The split group holding `id`, from the index kept with `splits` (same answer as searching them in order).
    func splitGroup(of id: String) -> [String]? {
        let splits = splits  // still tracked by observers
        guard let group = splitIndex[id] else { return nil }
        return group < splits.count && splits[group].contains(id) ? splits[group] : splits.first { $0.contains(id) }
    }
    static func splitIndex(_ splits: [[String]]) -> [String: Int] {
        var index: [String: Int] = [:]
        for (group, ids) in splits.enumerated() { for id in ids where index[id] == nil { index[id] = group } }
        return index
    }

    /// Cmd+Shift+D or "Open in Split View": add `other` (or a new tab) beside the active tab.
    func splitActive(with other: String? = nil, newTabURL: String = "https://duckduckgo.com") {
        guard let active = activeTabID else { return }
        guard (splitGroup(of: active)?.count ?? 1) < 4 else { return }
        let partner = other ?? newTab(url: newTabURL, select: false, after: active)?.id
        guard let partner, partner != active else { return }
        join(partner, to: active, leading: false)
    }

    /// Drag-to-split: show `id` on the left (`leading`) or right of the active tab.
    func splitWithDropped(_ id: String, leading: Bool) {
        splitWithDropped(id, edge: leading ? .left : .right)
    }

    /// Drag-to-split: add `id` to the active tab's group at the page edge it was dropped on.
    /// A first split goes side by side (left/right) or stacked (top/bottom); a bigger group
    /// becomes a grid when the edge cuts across its current direction.
    func splitWithDropped(_ id: String, edge: SplitEdge) {
        guard let dropped = tab(id), dropped.spaceID == activeSpaceID else { return }
        // A pane dragged by its header moves within its group (and may change the layout).
        if let active = activeTabID, let group = splitGroup(of: active), group.contains(id) {
            var others = group.filter { $0 != id }
            splitLayout = Self.layout(afterDropOn: edge, count: others.count, current: splitLayout)
            if edge.isLeading { others.insert(id, at: 0) } else { others.append(id) }
            splits = splits.map { $0 == group ? others : $0 }
            activeTabID = id
            scheduleSave()
            return
        }
        guard let active = activeTabID else { return }
        if active == id {
            guard let empty = newTab(url: InternalPage.splitEmpty.url, select: false, after: active) else { return }
            splitLayout = edge.isHorizontalAxis ? .columns : .rows
            join(empty.id, to: active, leading: !edge.isLeading)
            activeTabID = active
            scheduleSave()
            return
        }
        if let empty = (splitGroup(of: active) ?? []).first(where: { tab($0)?.url == InternalPage.splitEmpty.url }) {
            fillEmptySplit(empty, with: id)
            return
        }
        let count = splitGroup(of: active)?.count ?? 1
        guard count < 4 else { return }
        splitLayout = Self.layout(afterDropOn: edge, count: count, current: splitLayout)
        join(id, to: active, leading: edge.isLeading)
    }

    /// Replace the destination slot without changing its side or the group's layout.
    func fillEmptySplit(_ empty: String, with id: String) {
        guard empty != id, let placeholder = tab(empty), placeholder.url == InternalPage.splitEmpty.url,
              let dropped = tab(id), dropped.spaceID == placeholder.spaceID,
              let group = splitGroup(of: empty), !group.contains(id) else { return }
        removeFromSplits([id])
        guard let index = splits.firstIndex(where: { $0.contains(empty) }) else { return }
        splits[index] = group.map { $0 == empty ? id : $0 }
        select(id)
        closeTab(empty)
        scheduleSave()
    }

    /// The layout a group of `count` panes takes when another is dropped on `edge`.
    static func layout(afterDropOn edge: SplitEdge, count: Int, current: SplitLayout) -> SplitLayout {
        if count < 2 { return edge.isHorizontalAxis ? .columns : .rows }
        if current == .columns && !edge.isHorizontalAxis || current == .rows && edge.isHorizontalAxis { return .grid }
        return current
    }

    private func join(_ id: String, to active: String, leading: Bool) {
        if splitGroup(of: active)?.contains(id) == true || (splitGroup(of: active)?.count ?? 1) >= 4 { return }
        removeFromSplits([id])  // a tab lives in one group only
        var group = splitGroup(of: active) ?? [active]
        guard group.count < 4 else { return }
        splits.removeAll { $0.contains(active) }
        if leading { group.insert(id, at: 0) } else { group.append(id) }
        splits.append(group)
        activeTabID = id
        scheduleSave()
    }

    /// Separates every tab in the active tab's group.
    func unsplit() {
        guard let active = activeTabID else { return }
        unsplitGroup(containing: active)
    }

    func unsplitGroup(containing id: String) {
        splits.removeAll { $0.contains(id) }
        scheduleSave()
    }

    /// Takes one tab out of its group (the rest stay together if two or more remain).
    func separate(_ id: String) {
        removeFromSplits([id])
        scheduleSave()
    }

    func toggleSplitOrientation() {
        let count = visibleTabIDs.count
        splitLayout = splitLayout.next(count: count)
        scheduleSave()
    }

    /// Drops tabs from their groups; groups left with fewer than two tabs dissolve.
    func removeFromSplits(_ ids: Set<String>) {
        splits = splits.map { $0.filter { !ids.contains($0) } }.filter { $0.count >= 2 }
    }
}
