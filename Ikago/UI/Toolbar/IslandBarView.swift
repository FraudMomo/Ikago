import SwiftUI

/// Top Bar layout: a slim floating glass island. Tabs share a dynamic width;
/// the active tab shows the page; clicking it (or ⌘L) turns it into the address field. Split groups show as
/// one capsule. Crowded inactive tabs compact to favicons beside the readable active tab, then scroll.
/// The bar wears the page's theme color when the site has one (see `BrowserState.barTint`).
struct IslandBarView: View {
    let state: BrowserState
    let chrome: ChromeModel
    let palette: CommandPaletteModel
    weak var commands: BrowserCommands?
    var foldOutsideControls = false
    var reserveTrafficLights = false
    @Namespace private var selection
    @State private var scrollEdges = TabScrollEdges()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Built once per render, shared by the bar and the motion key.
        let sections = stripSections()
        return GeometryReader { geometry in
            bar(available: geometry.size.width, sections: sections)
                .frame(width: geometry.size.width, height: state.barShownHeight)
        }
        .frame(height: state.barShownHeight)
        .recordLayout("island")
        // Compact tab motion: tabs and groups grow in and shrink out while neighbours slide.
        .animation(.ikago, value: state.barTint)
        .tabStripMotion(TabMotionKey(ids: sections.map(\.id) + sections.flatMap(\.items).map(\.id)), space: state.activeSpaceID, reduceMotion: reduceMotion)
    }

    private var controlSize: CGFloat { 28 }
    /// Tabs and control capsules follow the adjustable row height.
    private var rowItemHeight: CGFloat { BrowserState.topBarControlHeight(in: state.barShownHeight) }

    private func bar(available: CGFloat, sections: [IslandStripSection]) -> some View {
        let colors = state.barPalette
        let items = sections.flatMap(\.items)
        let lights = state.barFloating || reserveTrafficLights
        let toolbar = IslandToolbarLayout(leading: leadingItems, trailing: trailingItems, available: available, floating: lights, size: controlSize)
        let viewport = max(32, toolbar.viewport - 16)
        // Readable titles first, then inactive tabs compact to favicons beside the active tab.
        let layout = TabStripLayout(items: items, available: viewport,
                                    expandedGroups: sections.filter(\.hasMembers).count,
                                    groupStyle: state.groupLabelStyle, showGroupCounts: state.showsGroupTabCounts, maximumTab: 280,
                                    activeID: state.activeTabID, minimumInactive: 34)
        let width = min(layout.natural, viewport)
        let target = scrollTarget(in: items)
        return HStack(spacing: 2) {
            if lights { Color.clear.frame(width: Self.lightsWidth, height: 1) }
            PrivateBadge(state: state, colors: colors).padding(.horizontal, 3)
            if !toolbar.leading.isEmpty {
                GlassControlGroup(colors: colors, height: rowItemHeight) {
                    HStack(spacing: 2) {
                        ForEach(toolbar.leading) { item in
                            ChromeItemView(item: item, state: state, colors: colors, commands: commands, size: controlSize)
                        }
                    }
                }
            }
            if lights { WindowDragArea().frame(minWidth: 0, maxWidth: .infinity) }
            ScrollViewReader { _ in
                ScrollView(.horizontal) {
                    HStack(spacing: TabStripLayout.spacing) {
                        ForEach(sections) { section in
                            sectionView(section, layout: layout, colors: colors, activeTarget: target)
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 3)
                }
                .onScrollGeometryChange(for: TabScrollEdges.self) { geometry in
                    TabScrollEdges(geometry)
                } action: { _, edges in
                    scrollEdges = edges
                    #if DEBUG
                    LayoutChecks.tabEdges = edges
                    #endif
                }
                .scrollIndicators(.never)
                .frame(width: width)
                .clipped()
                .recordLayout("tab-viewport")
                .mask(TabStripEdgeFade(edges: scrollEdges))
            }
            if lights { WindowDragArea().frame(minWidth: 0, maxWidth: .infinity) }
            if !toolbar.trailing.isEmpty {
                GlassControlGroup(colors: colors, height: rowItemHeight) {
                    HStack(spacing: 2) {
                        ForEach(toolbar.trailing) { item in
                            ChromeItemView(item: item, state: state, colors: colors, commands: commands, size: controlSize)
                        }
                    }
                }
            }
            if !toolbar.overflow.isEmpty {
                ChromeOverflowMenu(items: toolbar.overflow, state: state, colors: colors, size: controlSize, commands: commands)
            }
        }
        .padding(.horizontal, 3)
        .frame(maxWidth: .infinity)
        .frame(height: state.barShownHeight)
        // Like the sidebar: empty island space around and between tabs and controls moves the window.
        .background(WindowDragArea())
        .environment(\.colorScheme, colors.isDark ? .dark : .light)
        .stripDrop(state: state, chrome: chrome)
        .frame(maxWidth: .infinity)
    }

    private func scrollTarget(in items: [TabListItem]) -> String? {
        // A split can span folders. Prefer its visible row before falling back to a collapsed header.
        if let item = items.first(where: { $0.containsTab(state.activeTabID) }) { return item.id }
        return items.first { item in
            if case .folder(let folder, _) = item { return !folder.isOpen && folder.id == state.activeTab?.folderID }
            return false
        }?.id
    }

    /// Keep group members together on one surface, without changing their tab or split identities.
    private func stripSections() -> [IslandStripSection] {
        var seen = Set<String>()
        if !state.showsTopBarEssentials || !state.showsTopBarPins { seen = Set(state.topBarShelfPins.map(\.id)) }
        var sections = state.listItems(state.pinnedTabs, seen: &seen).map(IslandStripSection.item)
        for folder in state.stripFolders {
            let tabs = state.tabs(in: folder)
            let members = folder.isOpen ? state.listItems(tabs, seen: &seen) : []
            sections.append(.folder(folder, members, tabs.count))
            if !folder.isOpen { tabs.forEach { seen.insert($0.id) } }
        }
        return sections + state.listItems(state.looseTabs, seen: &seen).map(IslandStripSection.item)
    }

    /// Buttons placed outside the island live inside it in Floating mode (there is no bar around it).
    private var leadingItems: [ChromeItem] {
        state.chromeLayout.topBarLeading + (state.barFloating || foldOutsideControls ? state.chromeLayout.topBarOuterLeading : [])
    }
    private var trailingItems: [ChromeItem] {
        let placed = (state.barFloating || foldOutsideControls ? state.chromeLayout.topBarOuterTrailing : []) + state.chromeLayout.topBarTrailing
        let automatic = (DownloadCenter.shared.showsToolbarButton || chrome.showDownloads) && !state.chromeLayout.contains(.downloads, inTopBar: true)
        return placed + (automatic ? [.downloads] : [])
    }

    /// Room for the traffic lights at the island's leading end (Floating mode).
    static let lightsWidth: CGFloat = 80

    @ViewBuilder private func sectionView(_ section: IslandStripSection, layout: TabStripLayout, colors: Palette, activeTarget: String?) -> some View {
        switch section {
        case .item(let item):
            itemView(item, layout: layout, colors: colors).id(item.id)
        case .folder(let folder, let members, let count):
            IslandFolderGroup(folder: folder, count: count, hasMembers: !members.isEmpty,
                              height: rowItemHeight, colors: colors, state: state,
                              chrome: chrome, selection: selection, representsActiveTab: activeTarget == section.id, commands: commands) {
                ForEach(members) { item in
                    itemView(item, layout: layout, colors: colors).id(item.id)
                }
            }
            .id(section.id)
            .tabSlot()
        }
    }

    @ViewBuilder private func itemView(_ item: TabListItem, layout: TabStripLayout, colors: Palette) -> some View {
        switch item {
        case .tab(let tab):
            IslandTab(tab: tab, isActive: tab.id == state.activeTabID, width: layout.width(of: tab),
                      compact: layout.width(of: tab) < TabStripLayout.iconOnlyWidth, height: rowItemHeight, state: state, chrome: chrome, palette: palette, colors: colors,
                      selection: selection, commands: commands)
                .tabInteractions(tab, state: state, chrome: chrome, commands: commands)
                .tabSlot()
        case .folder: EmptyView() // Drawn by sectionView, together with its members.
        case .group(let tabs):
            IslandGroup(tabs: tabs, chipWidth: layout.chip, compact: layout.compact, height: rowItemHeight, state: state, chrome: chrome,
                        colors: colors, selection: selection, commands: commands)
                .tabSlot()
        }
    }
}

extension View {
    /// Dropping a tab on empty bar space moves it to the end, out of its folder (and split group).
    func stripDrop(state: BrowserState, chrome: ChromeModel) -> some View {
        openTabDrop(state: state, chrome: chrome) { id, _ in
            withAnimation(.ikago) {
                state.separate(id)
                state.move(id, before: nil, pinned: false, folderID: nil)
            }
        }
    }

    /// Click to select, right-click menu, drag to reorder or split.
    @ViewBuilder
    func tabInteractions(_ tab: TabItem, state: BrowserState, chrome: ChromeModel, commands: BrowserCommands?, drags: Bool = true,
                         beforeClose: @escaping () -> Void = { }) -> some View {
        let base = contextMenu { TabContextMenu(tab: tab, state: state, commands: commands) }
            .onMiddleClick { beforeClose(); withAnimation(.ikago) { commands?.closeTab(tab.id) } }
        if drags {
            base.onDrag {
                chrome.beginTabDrag(tab.id)
                return TabDrag.provider(tab.id)
            }
            .tabDropTarget(tab, axis: .horizontal, state: state, chrome: chrome)
        } else {
            base.tabDropTarget(tab, axis: .horizontal, state: state, chrome: chrome)
        }
    }
}
