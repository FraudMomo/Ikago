import SwiftUI

/// The Sidebar layout's optional tab row (Settings ▸ Appearance ▸ Layout ▸ Sidebar + Tabs): ungrouped tabs sit above the
/// page like folders' open documents, while the rail keeps the Space, pins and groups; with the rail hidden, pinned tabs
/// lead the row as icon-only tabs. The active tab is drawn in the
/// page's own color and meets the page card, so tab and page read as one sheet.
struct SidebarTopTabs: View {
    let state: BrowserState
    let chrome: ChromeModel
    weak var commands: BrowserCommands?
    /// Room on the leading edge for the window's traffic lights.
    var leadingReserve: CGFloat = 0
    @State private var hoveredID: String?
    @State private var edges = TabScrollEdges()
    /// Chrome's close behaviour: after a tab closes under the pointer, the others keep their width (the next tab's close
    /// button lands where the pointer already is) until the pointer leaves the row; then they reflow together.
    @State private var heldWidth: CGFloat?
    @State private var pointerInRow = false
    @State private var lastWidth = WidthMemory()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let tabHeight: CGFloat = 34
    /// Tall enough that the tabs centre on the sidebar's top row, level with the traffic lights.
    static func height(_ state: BrowserState) -> CGFloat { state.sidebarRowCenter + tabHeight / 2 }
    /// Keeps the first tab's flare clear of the page card's rounded corner.
    static let edgeInset: CGFloat = 16

    var body: some View {
        var seen = Set<String>()
        // Group chips and their tabs first (`TopRowEntry`, when groups show here), then the ungrouped tabs.
        let entries = TopRowEntry.row(state: state, seen: &seen)
        let items = entries.compactMap(\.item)
        // Without the rail, pinned tabs lead the row as icon-only tabs, so the tabs never depend on the sidebar.
        let pins = state.showsSidebarRail ? [] : state.pinnedTabs
        let pinsWidth = CGFloat(pins.count) * Self.pinnedWidth
        let chipsWidth = entries.reduce(CGFloat(0)) { total, entry in
            if case .chip(let folder, _) = entry { return total + Self.chipSlot(folder, state: state) }
            return total
        }
        let hiddenGroups = state.showsGroupsInTopBar && !state.closedFolders.isEmpty
        let colors = state.palette
        return GeometryReader { geometry in
            let leading = leadingReserve
            let rowHeight = Self.height(state)
            let available = max(60, geometry.size.width - leading - 44 - (hiddenGroups ? HiddenGroupsButton.width : 0))
            let forTabs = max(60, available - pinsWidth - chipsWidth)
            let slots = items.reduce(CGFloat(0)) { $0 + Self.slots(of: $1) }
            // Like Chrome: tabs share the row up to a comfortable width, keep a readable minimum, then scroll.
            let fitted = min(228, max(112, (forTabs - Self.edgeInset * 2) / max(1, slots)))
            let width = heldWidth.map { min($0, 228) } ?? fitted
            let _ = lastWidth.value = width
            let natural = items.reduce(Self.edgeInset * 2 + pinsWidth + chipsWidth) { $0 + width * Self.slots(of: $1) }
            HStack(spacing: 0) {
                Color.clear.frame(width: leading)
                if hiddenGroups {
                    HiddenGroupsButton(state: state, colors: colors)
                        .padding(.top, rowHeight - Self.tabHeight)
                        .transition(.opacity)
                }
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ForEach(pins) { tab in pinnedTab(tab, colors: colors).tabSlot() }
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            switch entry {
                            case .chip(let folder, let count):
                                TopBarGroupChip(folder: folder, count: count, state: state, chrome: chrome, colors: colors, commands: commands)
                                    .padding(.horizontal, 3)
                                    .frame(width: Self.chipSlot(folder, state: state), height: Self.tabHeight)
                                    .modifier(TopBarGroupLine(group: folder.isOpen ? folder : nil, active: false, colors: colors))
                                    .recordLayout("top-chip-\(folder.id)")
                                    .tabSlot()
                            case .item(let item, let group):
                                itemView(item, width: width * Self.slots(of: item), colors: colors,
                                         divider: showsDivider(after: item, next: entries[safe: index + 1]?.item), group: group)
                                    .tabSlot()
                            }
                        }
                    }
                    .coordinateSpace(name: "ikago-tab-document")
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, Self.edgeInset)
                }
                .revealActiveTab()
                .scrollIndicators(.never)
                .onScrollGeometryChange(for: TabScrollEdges.self) { geometry in
                    // Only fade for tabs beyond the edge, not for the strip's own end padding.
                    var value = TabScrollEdges()
                    value.leading = geometry.visibleRect.minX > Self.edgeInset
                    value.trailing = geometry.visibleRect.maxX < geometry.contentSize.width - Self.edgeInset
                    return value
                } action: { _, value in edges = value }
                .mask(TabStripEdgeFade(edges: edges))
                .onHover { inside in
                    pointerInRow = inside
                    if !inside, heldWidth != nil { heldWidth = nil }
                }
                .onChange(of: items.count) { old, new in if new > old { heldWidth = nil } }
                // Only as tall as the tabs: a scroll view takes every click in its frame, and the strip above the tabs
                // belongs to the window (drag to move, double-click to zoom).
                .frame(width: min(natural, available), height: Self.tabHeight)
                .frame(height: rowHeight, alignment: .bottom)
                .recordLayout("sidebar-top-tabs")
                SidebarTopNewTabButton(colors: colors) { commands?.newTab() }
                    .padding(.top, rowHeight - Self.tabHeight)
                Spacer(minLength: 0)
            }
            .frame(width: geometry.size.width, height: rowHeight, alignment: .leading)
        }
        .frame(height: Self.height(state))
        // Empty space in the row moves the window, as in every other bar.
        .background(WindowDragArea())
        .environment(\.colorScheme, colors.isDark ? .dark : .light)
        .stripDrop(state: state, chrome: chrome)
        .tabStripMotion(TabMotionKey(ids: pins.map(\.id) + entries.map(\.id), held: heldWidth != nil), space: state.activeSpaceID, reduceMotion: reduceMotion)
    }

    static let pinnedWidth: CGFloat = 44

    /// A group chip's slot in the row, with a little room on each side.
    static func chipSlot(_ folder: TabFolder, state: BrowserState) -> CGFloat {
        folder.chipWidth(showsCount: state.showsGroupTabCounts) + 6
    }

    private func pinnedTab(_ tab: TabItem, colors: Palette) -> some View {
        let active = tab.id == state.activeTabID
        let hover: (Bool) -> Void = { on in hoveredID = on ? tab.id : (hoveredID == tab.id ? nil : hoveredID) }
        return AttachedTab(width: Self.pinnedWidth, active: active, colors: colors, divider: false, sheet: state.tabSheetColor, onHover: hover) { _ in
            FaviconView(tab: tab, size: 15).opacity(tab.isUnloaded && !active ? 0.6 : 1)
        }
        .tabSelectionTint(chrome.selectedTabIDs.contains(tab.id), colors: colors)
        .onTapGesture { TabClick.handle(tab, state: state, chrome: chrome, commands: commands) { state.select(tab.id) } }
        .help(tab.displayTitle)
        .tabPeek(tab, commands: commands)
        .tabInteractions(tab, state: state, chrome: chrome, commands: commands)
    }

    private static func slots(of item: TabListItem) -> CGFloat {
        if case .group(let tabs) = item { return 0.6 * CGFloat(tabs.count) + 0.2 }
        return 1
    }

    private func isRaised(_ item: TabListItem?) -> Bool {
        guard let item else { return true }
        return item.containsTab(state.activeTabID) || item.id == hoveredID
    }

    /// A hairline separates two resting tabs; it disappears beside the active or hovered one.
    private func showsDivider(after item: TabListItem, next: TabListItem?) -> Bool {
        next != nil && !isRaised(item) && !isRaised(next)
    }

    @ViewBuilder private func itemView(_ item: TabListItem, width: CGFloat, colors: Palette, divider: Bool, group: TabFolder?) -> some View {
        itemBody(item, width: width, colors: colors, divider: divider)
            .modifier(TopBarGroupLine(group: group, active: item.containsTab(state.activeTabID), colors: colors))
    }

    @ViewBuilder private func itemBody(_ item: TabListItem, width: CGFloat, colors: Palette, divider: Bool) -> some View {
        let hover: (Bool) -> Void = { on in hoveredID = on ? item.id : (hoveredID == item.id ? nil : hoveredID) }
        switch item {
        case .tab(let tab):
            AttachedTab(width: width, active: tab.id == state.activeTabID, colors: colors, divider: divider, sheet: state.tabSheetColor, onHover: hover) { hovering in
                AttachedTabLabel(tab: tab, active: tab.id == state.activeTabID, hovering: hovering, colors: colors, commands: commands) {
                    // Set before the close, so the row never lays out once at the wider width.
                    if pointerInRow { heldWidth = lastWidth.value }
                    commands?.closeTab(tab.id)
                }
            }
            .tabSelectionTint(chrome.selectedTabIDs.contains(tab.id), colors: colors)
            .onTapGesture {
                TabClick.handle(tab, state: state, chrome: chrome, commands: commands) { state.select(tab.id) }
            }
            .tabPeek(tab, commands: commands)
            .tabInteractions(tab, state: state, chrome: chrome, commands: commands)
            .recordLayout("top-tab-\(tab.id)")
        case .group(let tabs):
            AttachedTab(width: width, active: tabs.contains { $0.id == state.activeTabID }, colors: colors, divider: divider, sheet: state.tabSheetColor, onHover: hover) { hovering in
                HStack(spacing: 2) {
                    ForEach(tabs) { tab in
                        SplitChip(tab: tab, focused: tab.id == state.activeTabID, colors: colors, compact: false, commands: commands)
                            .frame(maxWidth: .infinity).frame(height: Self.tabHeight - 10)
                            // On hover each pane's tab can be closed on its own, like any tab.
                            .overlay(alignment: .trailing) {
                                if hovering {
                                    SplitTabButton(symbol: "xmark", label: "Close Tab", colors: colors) { commands?.closeTab(tab.id) }
                                        .padding(.trailing, 4)
                                        .transition(.opacity)
                                }
                            }
                            .onTapGesture { state.select(tab.id) }
                            .tabInteractions(tab, state: state, chrome: chrome, commands: commands)
                    }
                }
                .padding(.horizontal, 6)
                // Between the panes' tabs, a button that takes them out of split view (both stay open).
                .overlay {
                    if hovering {
                        SplitTabButton(symbol: "rectangle.split.2x1", label: "Separate Tabs", colors: colors, filled: true) {
                            if let first = tabs.first { state.unsplitGroup(containing: first.id) }
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    }
                }
                .animation(.easeOut(duration: 0.12), value: hovering)
            }
        }
    }
}

/// The width the row last laid its tabs out at, kept outside SwiftUI's state so reading it never redraws the row.
private final class WidthMemory { var value: CGFloat = 0 }

/// One tab slot: the raised, page-colored sheet when active, a soft pill on hover, nothing at rest.
private struct AttachedTab<Label: View>: View {
    let width: CGFloat
    let active: Bool
    let colors: Palette
    let divider: Bool
    /// The tab's fill when active, shared with the address bar below it (`BrowserState.tabSheetColor`).
    let sheet: Color
    let onHover: (Bool) -> Void
    @ViewBuilder let label: (Bool) -> Label
    @State private var hovering = false
    @Environment(\.chromeModel) private var chrome

    var body: some View {
        label(hovering)
            .frame(width: width, height: SidebarTopTabs.tabHeight)
            .background {
                // No outline: the tab and the page are one sheet, and an edge would draw the seam between them.
                if active {
                    AttachedTabShape().fill(sheet)
                } else if hovering {
                    RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(colors.hover.opacity(1.6))
                        .padding(.vertical, 4).padding(.horizontal, 2)
                }
            }
            .overlay(alignment: .trailing) {
                Rectangle().fill(colors.separator.opacity(1.8)).frame(width: 1, height: 16)
                    .opacity(divider ? 1 : 0).allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            // Revealing the active tab includes its flares and the edge fade beside it, so it never looks cut off.
            .background(ActiveTabScrollAnchor(active: active).padding(.horizontal, -26))
            .recordLayout("active-tab", enabled: active)
            .onHover { inside in
                guard !inside || chrome?.coversTabs != true else { return }
                hovering = inside; onHover(inside)
            }
            .onChange(of: chrome?.coversTabs == true) { _, now in if now, hovering { hovering = false; onHover(false) } }
            .animation(.easeOut(duration: hovering ? 0.1 : 0.2), value: hovering)
    }
}

private struct AttachedTabLabel: View {
    let tab: TabItem
    let active: Bool
    let hovering: Bool
    let colors: Palette
    weak var commands: BrowserCommands?
    let close: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                FaviconView(tab: tab, size: 14).opacity(tab.isLoading ? 0.35 : 1)
                if tab.isLoading { ProgressView().controlSize(.mini).scaleEffect(0.6) }
            }
            .frame(width: 16, height: 16)
            Text(tab.displayTitle).font(.system(size: 12.5, weight: active ? .medium : .regular))
                .fadeTruncated()
                .frame(maxWidth: .infinity, alignment: .leading)
            TabMediaIndicators(tab: tab, colors: colors, commands: commands)
            // Resting tabs give the close button's room to their titles.
            if active || hovering {
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
                        .frame(width: 18, height: 18).contentShape(Circle())
                }
                .buttonStyle(CircleHoverButtonStyle(colors: colors))
                .help("Close Tab (⌘W)")
            }
        }
        .foregroundStyle(active ? colors.text : colors.secondary)
        .padding(.leading, 12).padding(.trailing, active || hovering ? 7 : 12)
        .opacity(tab.isUnloaded && !active ? 0.6 : 1)
    }
}

private struct SidebarTopNewTabButton: View {
    let colors: Palette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus").font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 28).contentShape(Circle())
        }
        .buttonStyle(CircleHoverButtonStyle(colors: colors))
        .glassControl(Circle(), colors)
        .foregroundStyle(colors.secondary)
        .frame(height: SidebarTopTabs.tabHeight)
        .padding(.leading, 2)
        .help("New Tab (⌘T)")
    }
}

/// A circle that fills on hover and darkens while pressed.
struct CircleHoverButtonStyle: ButtonStyle {
    let colors: Palette
    func makeBody(configuration: Configuration) -> some View { HoverCircle(configuration: configuration, colors: colors) }

    private struct HoverCircle: View {
        let configuration: Configuration
        let colors: Palette
        @State private var hovering = false
        var body: some View {
            configuration.label
                .background(Circle().fill(colors.hover.opacity(configuration.isPressed ? 2.6 : hovering ? 1.6 : 0)))
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
    }
}
