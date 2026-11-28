import Foundation
import SwiftUI

// MARK: - Bar
extension BrowserState {
    /// Settings ▸ Appearance ▸ Layout ▸ Top Tabs: tabs and an address bar above the page, and the sidebar only as
    /// a rail of icons or hidden (never the full sidebar).
    var usesTabsLayout: Bool { browserPreferences.sidebarTopTabs == true }
    /// The tab row and address bar are on screen (full screen gives the page the whole display).
    var showsSidebarTopTabs: Bool { usesTabsLayout && !isImmersive }
    /// The address bar under the tab row, part of the page's card: fixed.
    var tabsToolbarHeight: CGFloat { 34 }
    /// The address field and control groups inside it.
    var tabsFieldHeight: CGFloat { tabsToolbarHeight - 8 }
    /// The sidebar's top row (traffic lights and toolbar controls), measured from the window's top edge. Everything
    /// that shares that line, the lights, the sidebar's controls and the Top Tabs row, centres on `sidebarRowCenter`.
    var sidebarRowTop: CGFloat { max(8, CGFloat(frameInset)) }
    static let sidebarRowHeight: CGFloat = 36
    var sidebarRowCenter: CGFloat { sidebarRowTop + Self.sidebarRowHeight / 2 }
    /// The docked sidebar is part of the window's own surface (no card of its own), so only the page is a rounded card.
    /// Liquid Glass keeps its glass panel, except with the frosted sidebar: then the window itself is the frosted surface
    /// (`WindowBackgroundView`), and a card of its own would stack a second, flatter layer on it. In Top Tabs the
    /// rail is part of the window like the tab row beside it; only its controls are glass.
    var sidebarJoinsWindow: Bool { !useGlass || frostedChrome || usesTabsLayout }
    /// Settings ▸ Appearance ▸ translucent sidebar, unless macOS's Reduce Transparency is on: the window is frosted, and
    /// in Top Tabs the active tab and the address bar are one lighter, see-through sheet over it.
    var frostedChrome: Bool {
        browserPreferences.translucentSidebar == true && !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }
    /// The active tab and address bar's fill: the page's color, see-through when the window is frosted, so tab and bar
    /// read as one lighter sheet of the frost that settles into the solid page below.
    /// In dark mode over the frost a darker veil all but vanished into it, so the sheet lightens the frost instead.
    var tabSheetColor: Color {
        guard frostedChrome else { return palette.tabSheet }
        return palette.isDark ? Color.white.opacity(0.12) : palette.tabSheet.opacity(0.62)
    }
    /// The sidebar's three states: full, a rail of icons, or hidden (`sidebarVisible`).
    /// Top Tabs: how the address bar sits under the tabs.
    /// The style of the address bar on screen: Top Tabs' (`tabsAddressStyle`), or the Sidebar layout's bar above the
    /// page (`pageBarStyle`). Unset: Full Width.
    var tabsAddressStyle: TabsAddressStyle {
        (showsPageAddressBar ? browserPreferences.pageBarStyle : browserPreferences.tabsAddressStyle) ?? .wide
    }
    /// Sidebar layout with the address bar above the page (`addressAbovePage`): the bar is the top of the page's card,
    /// whatever the sidebar shows (full, icons or hidden), and the sidebar keeps no address field.
    var showsPageAddressBar: Bool { !usesTabsLayout && !isImmersive && webApp == nil && browserPreferences.addressAbovePage == true }
    /// A bar is the top of the page's card (Top Tabs' address bar, or the Sidebar layout's above the page): the page's
    /// top corners are square under it.
    var pageHasTopBar: Bool { showsSidebarTopTabs || showsPageAddressBar }
    /// A hidden sidebar slides in at the window's edge: every mode but Off.
    var sidebarEdgePeek: Bool { browserPreferences.sidebarEdgePeek ?? true }
    /// The sidebar as Settings offers it: Full, Icons, Hidden (it slides in at the window's edge) or Off. Top Tabs has
    /// no full sidebar: its Icons is the rail.
    var sidebarMode: SidebarMode {
        get { sidebarVisible ? (showsSidebarRail ? .icons : .full) : (sidebarEdgePeek ? .hidden : .off) }
        set {
            sidebarVisible = newValue == .full || newValue == .icons
            if sidebarVisible { browserPreferences.sidebarCompact = newValue == .icons ? true : nil }
            browserPreferences.sidebarEdgePeek = newValue == .off ? false : nil
            // With no sidebar at all, Top Tabs' groups go to the tab row, where they can still be seen.
            if newValue == .off && usesTabsLayout { browserPreferences.groupPlacement = nil }
        }
    }
    /// Top Tabs: with essentials on, pinned tabs live in the icon sidebar, also while it is hidden and slides in at
    /// the window's edge. They lead the tab row as icon tabs only when essentials are off, or when the sidebar is hidden
    /// and can't slide in (edge peek off), so they are never out of reach.
    var pinsInTabRow: Bool { !showsPinnedGrid || (!showsSidebarRail && !sidebarEdgePeek) }
    /// Top Tabs in split view: each pane has its own bar (back, forward, reload, its address, close) instead of the one
    /// address bar above the page (`PaneBar`).
    var showsPaneBars: Bool { showsSidebarTopTabs && activeTabID.flatMap { splitGroup(of: $0) } != nil }
    /// Pins show in one place: the rail has them whenever the tab row doesn't.
    var pinsInRail: Bool { showsPinnedGrid && !(usesTabsLayout && pinsInTabRow) }

    var showsSidebarRail: Bool { sidebarVisible && (browserPreferences.sidebarCompact == true || usesTabsLayout) }
    /// The rail's width: room for the traffic lights side by side, and a 36 pt tile.
    static let sidebarRailWidth: CGFloat = 64

    var pageCornerRadius: CGFloat { frameInset == 0 || isImmersive ? 0 : Radius.card }
}

extension BrowserState {
    /// The retired shortcut rows, once: a row that opened a page becomes a pinned row in every Space, above the
    /// essentials grid where the rows were above it; the assistant and Notes, which aren't pages, become controls in the
    /// sidebar's top row; the Space header becomes the Spaces control. The old fields are then cleared.
    func convertSidebarShortcuts() {
        let old = browserPreferences
        browserPreferences.sidebarShortcuts = nil
        browserPreferences.sidebarShortcutItems = nil
        browserPreferences.pinnedGridAboveShortcuts = nil
        guard old.sidebarShortcuts == true else { return }
        let items = old.sidebarShortcutItems ?? ["assistant", "bookmarks", "history"]
        let pages = items.compactMap(InternalPage.init(rawValue:)).filter { $0 != .notes }
        for item in items.compactMap(ChromeItem.init(rawValue:)) where (item == .assistant || item == .notes) && !chromeLayout.contains(item) {
            chromeLayout.place(item, in: .sidebarTop)
        }
        if !chromeLayout.contains(.spaces, in: .sidebarTop) { chromeLayout.place(.spaces, in: .sidebarBottom) }
        for space in spaces {
            let new = pages.filter { page in !tabs.contains { $0.spaceID == space.id && $0.pinned && $0.url == page.url } }.map { page in
                let tab = TabItem(url: page.url, title: page.title, pinned: true, spaceID: space.id)
                tab.pinAsRow = true
                tab.pinAboveGrid = old.pinnedGridAboveShortcuts != true
                return tab
            }
            tabs.insert(contentsOf: new, at: 0)
        }
        tabs = tabs.filter(\.pinned) + tabs.filter { !$0.pinned }
    }

    /// Seed the sidebar's toolbar on enable; later customization, including removal, survives relaunch.
    func preparePageAssistantToolbar() {
        if !chromeLayout.contains(.assistant) { chromeLayout.add(.assistant) }
        browserPreferences.assistantToolbarInitialized = true
    }

    /// Optional features keep their saved placement while hidden from the live toolbar.
    func visibleChromeItems(_ items: [ChromeItem]) -> [ChromeItem] {
        items.filter { $0 != .assistant || browserPreferences.pageIntelligence == true }
    }

    /// Groups are hidden and the Tab Groups button isn't placed in `zone`'s family: that place shows it anyway, so a
    /// hidden group is never out of reach.
    func addsTabGroupsButton(in zone: ChromeZone) -> Bool {
        !closedFolders.isEmpty && !chromeLayout.contains(.tabGroups, in: zone)
    }
}

// MARK: - Split
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
    func splitActive(with other: String? = nil, newTabURL: String? = nil) {
        guard let active = activeTabID else { return }
        guard (splitGroup(of: active)?.count ?? 1) < 4 else { return }
        let partner = other ?? newTab(url: newTabURL ?? startPageURL, select: false, after: active)?.id
        guard let partner, partner != active else { return }
        join(partner, to: active, leading: false)
    }

    /// A tab dropped on another tab's split half: the two side by side (or the dropped one added to the target's group),
    /// showing the target.
    func splitTabs(_ id: String, with targetID: String) {
        guard id != targetID, tab(id) != nil, tab(targetID) != nil else { return }
        select(targetID)
        join(id, to: targetID, leading: false)
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

// MARK: - Peek
/// When a clicked link opens in Peek (Settings ▸ Tabs ▸ Peek).
enum LinkPeek: String, Codable, CaseIterable, Identifiable {
    case off, shiftClick, automatic
    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: "Off"
        case .shiftClick: "Shift-Click"
        case .automatic: "Automatically"
        }
    }
}

/// How a link was clicked: with Shift, as a link that opens a new tab (target=_blank), or as a plain link.
enum PeekTrigger { case shiftClick, newTabLink, link }

extension BrowserState {
    /// Whether `url`, clicked in `tab` showing `pageURL`, opens in Peek. Shift-click peeks unless Peek is off; with
    /// Automatic, so do links to another site from a pinned tab or a search results page, and, if chosen, every link
    /// that would open a new tab.
    func peeks(_ url: URL, trigger: PeekTrigger, in tab: TabItem, pageURL: String) -> Bool {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return false }
        let mode = browserPreferences.linkPeek ?? .shiftClick
        if trigger == .shiftClick { return mode != .off }
        guard mode == .automatic else { return false }
        let preferences = browserPreferences
        if trigger == .newTabLink, preferences.peekNewTabLinks == true { return true }
        guard Self.otherSite(url, from: pageURL) else { return false }
        if tab.pinned, preferences.peekPinnedLinks != false { return true }
        return OmniboxURL.searchTerms(pageURL) != nil && preferences.peekSearchResults != false
    }

    private static func otherSite(_ url: URL, from pageURL: String) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        guard let from = URLComponents(string: pageURL)?.host?.lowercased() else { return true }
        return PublicSuffix.registrableDomain(host) != PublicSuffix.registrableDomain(from)
    }
}

enum SidebarMode: Hashable {
    case full, icons, hidden, off
}
