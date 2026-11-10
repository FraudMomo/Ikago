import SwiftUI

/// The Separate style gives tabs an even share of the row, compacts inactive tabs to favicons
/// once titles would no longer fit, then scrolls.
struct TopTabStrip: View {
    let state: BrowserState
    let chrome: ChromeModel
    weak var commands: BrowserCommands?
    @Namespace private var selection
    @State private var edges = TabScrollEdges()
    @State private var hoveredTabID: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Built once per render and shared: the strip, the motion key and the folder chips all need it.
        let items = stripItems()
        let selected = target(in: items)
        return GeometryReader { geometry in
            let colors = state.topBarPalette
            let height = state.topTabBarHeight
            // Tabs share the row down to a readable width, then inactive tabs compact to favicons.
            let layout = TabStripLayout(items: items, available: geometry.size.width, groupStyle: state.groupLabelStyle,
                showGroupCounts: state.showsGroupTabCounts, maximumTab: .greatestFiniteMagnitude, pinnedWidth: 36,
                activeID: state.activeTabID, minimumInactive: 40)
            ScrollViewReader { _ in
                ScrollView(.horizontal) {
                    HStack(spacing: TabStripLayout.spacing) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            itemView(item, next: items.indices.contains(index + 1) ? items[index + 1] : nil,
                                     layout: layout, colors: colors, height: height - 8, selected: selected).id(item.id)
                                .tabSlot()
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false).padding(.horizontal, 3)
                }
                .scrollIndicators(.never)
                .onScrollGeometryChange(for: TabScrollEdges.self) { TabScrollEdges($0) } action: { _, value in
                    edges = value
                    #if DEBUG
                    LayoutChecks.tabEdges = value
                    #endif
                }
                .mask(TabStripEdgeFade(edges: edges))
                .frame(width: geometry.size.width, height: height)
                .recordLayout("tab-viewport")
            }
        }
        .frame(height: state.topTabBarHeight)
        .overlay(alignment: .top) { Rectangle().fill(state.topBarPalette.separator.opacity(0.7)).frame(height: 0.5).allowsHitTesting(false) }
        .recordLayout("connected-tab-row")
        .stripDrop(state: state, chrome: chrome)
        // Tab motion: opened tabs grow in, closed tabs shrink out, neighbours slide (`TabMotion`).
        .tabStripMotion(TabMotionKey(ids: items.map(\.id)), space: state.activeSpaceID, reduceMotion: reduceMotion)
    }

    private func stripItems() -> [TabListItem] {
        var seen = Set<String>()
        if !state.showsTopBarEssentials || !state.showsTopBarPins { seen = Set(state.topBarShelfPins.map(\.id)) }
        var items = state.listItems(state.pinnedTabs, seen: &seen)
        for folder in state.stripFolders {
            let tabs = state.tabs(in: folder)
            items.append(.folder(folder, tabs.count))
            if folder.isOpen { items += state.listItems(tabs, seen: &seen) }
            else { tabs.forEach { seen.insert($0.id) } }
        }
        return items + state.listItems(state.looseTabs, seen: &seen)
    }

    private func target(in items: [TabListItem]) -> String? {
        if let item = items.first(where: { $0.containsTab(state.activeTabID) }) { return item.id }
        return items.first {
            if case .folder(let folder, _) = $0 { return folder.id == state.activeTab?.folderID }
            return false
        }?.id
    }

    /// Dividers separate neighbouring inactive tabs; the active and hovered tab drop their dividers.
    private func divider(after tab: TabItem, next: TabListItem?) -> Bool {
        guard let next, tab.id != state.activeTabID, tab.id != hoveredTabID else { return false }
        if case .tab(let other) = next { return other.id != state.activeTabID && other.id != hoveredTabID }
        return true
    }

    @ViewBuilder private func itemView(_ item: TabListItem, next: TabListItem?, layout: TabStripLayout, colors: Palette, height: CGFloat,
                                       selected: String?) -> some View {
        switch item {
        case .tab(let tab):
            TopTabView(tab: tab, state: state, colors: colors, width: layout.width(of: tab), height: height, selection: selection,
                          commands: commands, showsDivider: divider(after: tab, next: next),
                          onHover: { hoveredTabID = $0 ? tab.id : (hoveredTabID == tab.id ? nil : hoveredTabID) })
                .tabInteractions(tab, state: state, chrome: chrome, commands: commands)
        case .folder(let folder, let count):
            FolderChip(folder: folder, count: count, height: height, colors: colors, state: state, chrome: chrome,
                       selection: selection, isSelected: selected == item.id, commands: commands)
        case .group(let tabs):
            IslandGroup(tabs: tabs, chipWidth: layout.chip, compact: false, height: height, state: state, chrome: chrome,
                        colors: colors, selection: selection, commands: commands)
        }
    }
}

private struct TopTabView: View {
    let tab: TabItem
    let state: BrowserState
    let colors: Palette
    let width: CGFloat
    let height: CGFloat
    let selection: Namespace.ID
    weak var commands: BrowserCommands?
    var showsDivider = false
    var onHover: (Bool) -> Void = { _ in }
    @State private var hovering = false
    private var active: Bool { tab.id == state.activeTabID }
    /// A compacted inactive tab: its favicon, swapped for the close button on hover.
    private var iconOnly: Bool { !tab.pinned && !active && width < TabStripLayout.iconOnlyWidth }

    var body: some View {
        Group {
            if iconOnly {
                ZStack {
                    if tab.isMuted || tab.isPlayingAudio {
                        TabAudioButton(tab: tab, colors: colors, commands: commands)
                    } else {
                        FaviconView(tab: tab, size: 14).opacity(hovering ? 0 : tab.isLoading ? 0.4 : 1)
                        if hovering { closeButton }
                    }
                }
                .frame(maxWidth: .infinity)
            } else {
                label
            }
        }
        .padding(.horizontal, 6).frame(width: width, height: height)
        .foregroundStyle(active ? colors.text : colors.secondary)
        .background {
            let fill = RoundedRectangle(cornerRadius: min(10, height / 2), style: .continuous)
            if active && !colors.isDark { CardShadow(shape: fill, color: .black.opacity(0.08), radius: 1, y: 0.5) }
            fill
                .fill(active ? Color(nsColor: state.topBarAddressColor) : colors.hover.opacity(1.4))
                .opacity(active || hovering ? 1 : 0)
                .animation(nil, value: active)  // selection stays immediate inside the strip's motion
        }
        .overlay(alignment: .trailing) {
            Rectangle().fill(colors.separator.opacity(1.6)).frame(width: 1, height: height * 0.5)
                .offset(x: TabStripLayout.spacing / 2 + 0.5).opacity(showsDivider ? 1 : 0)
        }
        .background(ActiveTabScrollAnchor(active: active))
        .contentShape(Rectangle())
        .onTapGesture { state.select(tab.id) }
        .onHover { inside in hovering = inside; onHover(inside) }
        .animation(.easeOut(duration: hovering ? 0.1 : 0.2), value: hovering)
        .recordLayout("regular-tab-\(tab.id)", enabled: !tab.pinned)
        .recordLayout("topbar-pin-\(tab.id)", enabled: tab.pinned)
        .recordLayout("active-tab", enabled: active)
        .help(tab.displayTitle)
    }

    private var label: some View {
        HStack(spacing: 6) {
            if !tab.pinned {
                closeButton.opacity(hovering ? 1 : 0).allowsHitTesting(hovering)
                Spacer(minLength: 0)
            }
            if tab.pinned && (tab.isMuted || tab.isPlayingAudio) {
                TabAudioButton(tab: tab, colors: colors, commands: commands)
            } else {
                FaviconView(tab: tab, size: 14).opacity(tab.isLoading ? 0.4 : 1)
            }
            if !tab.pinned {
                Text(tab.displayTitle).font(.system(size: 12, weight: active ? .medium : .regular)).lineLimit(1)
                Spacer(minLength: 0)
                TabMediaIndicators(tab: tab, colors: colors, commands: commands)
                Color.clear.frame(width: 18, height: 1)
            }
        }
    }

    private var closeButton: some View {
        Button { commands?.closeTab(tab.id) } label: {
            Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)).frame(width: 18, height: 18)
                .background(Circle().fill(colors.hover.opacity(1.5)).opacity(hovering ? 1 : 0))
                .contentShape(Circle())
        }
        .buttonStyle(.plain).foregroundStyle(colors.secondary).help("Close Tab (⌘W)")
    }
}
