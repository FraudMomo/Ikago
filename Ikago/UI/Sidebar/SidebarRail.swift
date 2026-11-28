import SwiftUI

/// The Sidebar layout's middle state: a slim rail of icons beside the page. The traffic lights stand in a
/// column at the top (Ikago draws them there, `FullScreenWindowControls`), then in the full sidebar's order the essentials
/// (pinned tabs) as tiles, groups as one tile each (their icon in their colour; a click opens them in place), a line, a
/// new-tab button and the loose tabs, and at the bottom the Spaces and the
/// placed controls (the sidebar button by default, which moves on to the next sidebar state). Titles show on hover; the active tab's highlight slides between tiles.
struct SidebarRail: View {
    let state: BrowserState
    let chrome: ChromeModel
    weak var commands: BrowserCommands?
    /// Magnify's copy of the rail (`RailMagnifyLayer`): only the icons, in the same places, growing in the carousel; drawn
    /// over the rail, whose tiles stay and whose own icons step aside, so the rows can lie between the tiles and icons.
    var magnified = false
    /// One of the copies drawn over the rail by the hover effects, not the rail in the window.
    private var isCopy: Bool { magnified }
    /// This rail for the hover effects (`RailHover`): where its tiles measure themselves (the rail, and its list's own
    /// host), kept apart from any other rail on screen.
    @State private var surface = RailSurface()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Room for the three traffic lights in a column.
    static let lightsHeight: CGFloat = 78

    var body: some View {
        let colors = state.palette
        let model = chrome.rail
        // Leading-aligned, with every item in the rail's 64 pt column (tiles 14 pt in), so Expand's sidebar keeps each icon
        // exactly where the rail has it and only the names grow out.
        VStack(alignment: .leading, spacing: 8) {
            // Under the Top Tabs row the lights stay in that row, beside the tabs.
            Color.clear.frame(height: state.showsSidebarTopTabs ? 4 : Self.lightsHeight)
            // The sidebar button sits where the full sidebar has it: at the top when its top row holds it.
            if toggleOnTop {
                sidebarToggle(colors)
                    .padding(.leading, Self.tileInset)
                    .opacity(magnified ? 0 : 1)
                    .modifier(RailButtonArea(key: "top", model: model, reports: !isCopy))
            }
            // Essentials: pinned tabs as tiles at the top (Settings ▸ Show essentials). Off, they are ordinary tiles in the
            // list, or in Top Tabs icon tabs at the start of the tab row.
            if !state.pinnedTabs.isEmpty && state.pinsInRail {
                VStack(spacing: 6) {
                    ForEach(state.pinnedTabs) { tab in tabTile(tab, colors: colors, essential: true) }
                }
                .padding(.leading, Self.tileInset)
            }
            // Top Tabs: loose tabs and the + live in the tab row; the rail keeps pins and groups, under a line.
            if state.showsSidebarTopTabs && !state.pinnedTabs.isEmpty && state.pinsInRail {
                Capsule().fill(colors.separator).frame(width: 20, height: 1).frame(width: BrowserState.sidebarRailWidth)
                    .opacity(magnified ? 0 : 1)
            }
            // The full sidebar's order and list (`SidebarOutlineList`): pinned tabs, groups, a line, New Tab, then the
            // tabs, as tiles. Rows lift and move like the full sidebar's, with the same slot where they will land.
            SidebarOutlineList(state: state, chrome: chrome, colors: colors, commands: commands,
                               rail: railCells(colors, model: model))
            .frame(maxHeight: .infinity)
            // The foot stays a column of icons, wider or not.
            Group {
                if state.spaces.count > 1 { spaces(colors) }
                ForEach(footItems) { item in
                    if item == .sidebarToggle {
                        sidebarToggle(colors)
                    } else {
                        ChromeItemView(item: item, state: state, colors: colors, commands: commands, size: 32)
                            .recordLayout("rail-foot-\(item.rawValue)", enabled: !magnified)
                    }
                }
            }
            .opacity(magnified ? 0 : 1)
            .frame(width: BrowserState.sidebarRailWidth)
            .modifier(RailButtonArea(key: "foot", model: model, reports: !isCopy))
        }
        .padding(.bottom, 10)
        // While Expand's sidebar lies over this one, this one's items step aside: through a see-through material they
        // would show twice. (Not 0: SwiftUI stops hit-testing a view it no longer draws.)
        .opacity(!isCopy && model.covered && model.effect == .expand && model.surface === surface ? 0.001 : 1)
        .animation(nil, value: model.covered)
        .frame(width: width, alignment: .leading)
        .railSpace(surface.rail)
        .environment(\.railHover, effect == .magnify ? model : nil)
        .environment(\.railCopy, magnified)
        // Tabs' hover cards would cover the effects' names.
        .environment(\.tabHoverCards, effect == nil)
        // Only starts the effects: from then on their state machine reads the pointer itself (`RailHoverModel`).
        .background { if !isCopy, effect != nil { RailPointerTracker { if let point = $0 { model.pointerMoved(point, rail: surface, effect: effect) } } } }
        .onAppear { if isCopy { model.adoptOverlayList(surface.list) } else { model.appeared(surface) } }
        .onChange(of: effect) { if !isCopy { model.reset() } }
        .onDisappear { if !isCopy { model.disappeared(surface) } }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(SidebarSpaceSwipe(state: state))
        .background { if !isCopy { WindowDragArea() } }
        // The wider rail is sized to the rail's own frame, which already reaches under the title bar.
        .ignoresSafeArea(.container, edges: isCopy ? [] : .top)
        .animation(.ikagoQuick, value: state.activeTabID)
    }

    /// Anything above the New Tab tile (essentials, pinned tiles, groups), so the line before it separates something.
    private var hasItemsAboveNewTab: Bool {
        !state.pinnedTabs.isEmpty || (state.showsGroupsInSidebar && !state.blockFolders.isEmpty)
    }

    /// Tiles sit this far in from the rail's leading edge: a 36 pt tile centred in its 64 pt column.
    static let tileInset: CGFloat = (BrowserState.sidebarRailWidth - 36) / 2
    private var width: CGFloat { BrowserState.sidebarRailWidth }

    /// The hover effect in use: none under Reduce Motion.
    private var effect: RailHoverEffect? {
        reduceMotion ? nil : state.browserPreferences.railHover
    }

    /// The controls at the rail's foot (Settings ▸ Sidebar & Toolbar ▸ Customize ▸ Icons-only sidebar). Downloads join
    /// them while there are any, unless a toolbar above the page already shows them.
    private var footItems: [ChromeItem] {
        var items = state.visibleChromeItems(state.chromeLayout.rail).filter { ($0 != .spaces || state.spaces.count < 2) && !($0 == .sidebarToggle && toggleOnTop) }
        if !state.usesTabsLayout, !items.contains(.downloads), DownloadCenter.shared.showsToolbarButton { items.append(.downloads) }
        if state.addsTabGroupsButton(in: .rail) { items.append(.tabGroups) }
        return items
    }

    /// The rail shows the sidebar button (Customize ▸ Icons-only sidebar) and the full sidebar keeps its own in the top
    /// row: then the rail's goes to the top too, under the traffic lights, instead of the foot. Not under Top Tabs, whose
    /// toolbar holds it.
    private var toggleOnTop: Bool { Self.togglesAtTop(state) }

    static func togglesAtTop(_ state: BrowserState) -> Bool {
        let layout = state.chromeLayout
        return !state.showsSidebarTopTabs && layout.rail.contains(.sidebarToggle)
            && layout.sidebarTop.contains(.sidebarToggle)
    }

    /// Opens the full sidebar from the icons (the next step up); its menu hides the sidebar. Under Top Tabs, which has no
    /// full sidebar, it hides the rail.
    private func sidebarToggle(_ colors: Palette) -> some View {
        let tabs = state.usesTabsLayout
        return tile(symbol: "sidebar.left", label: tabs ? "Hide Sidebar" : "Show Full Sidebar", colors: colors, named: false) {
            if tabs { commands?.cycleSidebar() } else { commands?.showFullSidebar() }
        }
        .recordLayout("rail-sidebar-toggle", enabled: !magnified)
        .contextMenu {
            if !tabs { Button("Show Full Sidebar") { commands?.showFullSidebar() } }
            Button("Hide Sidebar") { withAnimation(.ikago) { state.sidebarVisible = false } }
        }
    }

    // MARK: Groups

    /// The rail's list as tiles (`OutlineRailCells`): a tab, a split row's tabs stacked, a group, the New Tab tile.
    private func railCells(_ colors: Palette, model: RailHoverModel) -> OutlineRailCells {
        let state = state
        let rowsAbove = hasItemsAboveNewTab
        return OutlineRailCells(
            cell: { row in
                switch row.kind {
                case .tabs(let ids):
                    return AnyView(VStack(alignment: .leading, spacing: 4) {
                        ForEach(ids.compactMap(state.tab)) { tab in tabTile(tab, colors: colors, listed: true) }
                    })
                case .group(let id):
                    guard let folder = state.folders.first(where: { $0.id == id }) else { return AnyView(EmptyView()) }
                    return AnyView(groupTile(folder, colors: colors))
                case .divider:
                    return AnyView(VStack(alignment: .leading, spacing: 4) {
                        if rowsAbove {
                            Capsule().fill(colors.separator).frame(width: 20, height: 1).frame(width: 36)
                                .padding(.vertical, 4)
                                .opacity(magnified ? 0 : 1)
                        }
                        tile(symbol: "plus", label: "New Tab", colors: colors) { commands?.newTab() }
                    })
                case .essentials:
                    return AnyView(EmptyView())
                }
            },
            height: { row in
                switch row.kind {
                case .tabs(let ids): CGFloat(ids.count) * 36 + CGFloat(max(0, ids.count - 1)) * 4
                case .group: 36
                case .divider: rowsAbove ? 32 + 9 + 4 : 32
                case .essentials: 0
                }
            },
            filter: { outline in
                // Essentials (or the tab row under Top Tabs) show every pin; groups kept in the tab row stay there.
                let pinsElsewhere = state.showsPinnedGrid || state.showsSidebarTopTabs
                let groups = state.showsGroupsInSidebar
                @MainActor func keep(_ rows: [SidebarOutline.Row]) -> [SidebarOutline.Row] {
                    rows.compactMap { row in
                        if row.groupID != nil {
                            guard groups else { return nil }
                            var row = row
                            row.children = keep(row.children)
                            return row
                        }
                        if pinsElsewhere, let id = row.tabIDs.first, state.tab(id)?.pinned == true { return nil }
                        return row
                    }
                }
                return SidebarOutline(rows: keep(outline.rows))
            },
            space: surface.list,
            onScroll: { [surface] in model.listScrolled(surface.list) },
            inset: Self.tileInset)
    }

    /// A group's tile: its icon in its colour (faded while its tabs sleep) and a count badge; a click (the list's) opens
    /// or shuts it, and its tabs follow it as tiles of their own.
    private func groupTile(_ folder: TabFolder, colors: Palette) -> some View {
        let tabs = state.tabs(inSubtree: folder)
        let open = folder.isOpen
        return railIcon(folder.name, colors: colors) {
            FolderIcon(folder: folder, colors: colors, size: 15)
                .railMagnify(.folder(folder.id), iconSize: 15)
                .opacity(TabItem.allAsleep(tabs, activeID: state.activeTabID) && !open ? 0.45 : 1)
                .frame(width: 36, height: 36)
        }
        .frame(height: 36)
        .background {
            // An active tab hidden in a closed group still shows where it is.
            TabSelectionHighlight(shape: RoundedRectangle(cornerRadius: Radius.row, style: .continuous),
                                  active: !open && !magnified && tabs.contains { $0.id == state.activeTabID }, color: colors.selected)
        }
        .contentShape(RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
        .modifier(RailTileHover(colors: colors, quiet: magnified))
        .help(effect != nil ? "" : "\(folder.name) · \(tabs.count) \(tabs.count == 1 ? "tab" : "tabs")")
        .contextMenu { FolderContextMenu(folder: folder, state: state, commands: commands) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(folder.name)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Tiles

    /// A tab's tile. In the list (`listed`) the list takes its clicks and drags (select, lift and move); Essentials are
    /// buttons with their own drags.
    @ViewBuilder
    private func tabTile(_ tab: TabItem, colors: Palette, essential: Bool = false, listed: Bool = false) -> some View {
        let active = tab.id == state.activeTabID
        let face = railIcon(tab.displayTitle, colors: colors) {
            FaviconView(tab: tab, size: essential ? 18 : 16)
                .railMagnify(.tab(tab.id), iconSize: essential ? 18 : 16)
                .opacity(tab.isUnloaded && !active ? 0.55 : 1)
                .frame(width: 36, height: 36)
        }
            .frame(height: 36)
            .background {
                if essential && !colors.glass && !magnified {
                    RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(colors.text.opacity(0.06))
                }
            }
            // Essentials are glass tiles with Liquid Glass on, like the sidebar's pinned grid.
            .glassControl(RoundedRectangle(cornerRadius: Radius.row, style: .continuous), colors, active: essential && !magnified)
            .background {
                TabSelectionHighlight(shape: RoundedRectangle(cornerRadius: Radius.row, style: .continuous), active: active && !magnified,
                                      color: colors.selected)
            }
            .contentShape(RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
        if listed {
            face
                .modifier(RailTileHover(colors: colors, quiet: magnified))
                .modifier(RailTileExtras(tab: tab, colors: colors, magnified: magnified, state: state, commands: commands))
                .accessibilityElement(children: .combine)
                .accessibilityLabel(tab.displayTitle)
                .accessibilityAddTraits(.isButton)
        } else {
            Button { if NSEvent.modifierFlags.contains(.option) { commands?.peekTab(tab.id) } else { state.select(tab.id) } } label: { face }
                .buttonStyle(RailButtonStyle(colors: colors, quiet: magnified))
                .modifier(RailTileExtras(tab: tab, colors: colors, magnified: magnified, state: state, commands: commands))
                // Essentials' drags: reorder among them, onto the page to split it, or out of the window into a new one.
                .onDrag {
                    chrome.beginTabDrag(tab.id)
                    return TabDrag.provider(tab.id)
                } preview: {
                    TabDragPreview(tab: tab, colors: colors, count: chrome.selectedTabIDs.contains(tab.id) ? chrome.selectedTabIDs.count : 1)
                }
                .tabDropTarget(tab, axis: .vertical, state: state, chrome: chrome)
        }
    }

    /// A tile's icon in its 36 pt box. Its name shows on hover, or in Magnify's tab row (`RailMagnifyRow`).
    private func railIcon<Icon: View>(_ name: String? = nil, colors: Palette, @ViewBuilder _ icon: () -> Icon) -> some View {
        icon().frame(width: 36)
    }

    private func spaces(_ colors: Palette) -> some View {
        VStack(spacing: 2) {
            ForEach(state.spaces) { space in
                let active = space.id == state.activeSpaceID
                Button { withAnimation(.ikago) { state.switchSpace(space.id) } } label: {
                    Image(systemName: space.symbol)
                        .font(.system(size: 12, weight: active ? .semibold : .regular))
                        .foregroundStyle(active ? colors.text : colors.tertiary)
                        .frame(width: 30, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(space.name)
            }
        }
    }

    private func tile(symbol: String, label: String, colors: Palette, named: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            railIcon(named ? label : nil, colors: colors) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(colors.secondary)
                    .modifier(RailNewTabMagnify(magnifies: named && symbol == "plus"))
                    .frame(width: 36, height: 32)
            }
                .frame(height: 32)
                .contentShape(RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
                .glassControl(RoundedRectangle(cornerRadius: Radius.row, style: .continuous), colors, active: !magnified)
        }
        .buttonStyle(RailButtonStyle(colors: colors, quiet: magnified))
        .help(effect != nil && named ? "" : label)
        .accessibilityLabel(label)
    }
}

/// A tab tile's sound badge, hover card and menu.
private struct RailTileExtras: ViewModifier {
    let tab: TabItem
    let colors: Palette
    let magnified: Bool
    let state: BrowserState
    weak var commands: BrowserCommands?

    func body(content: Content) -> some View {
        content
            // A mute badge on the tile while it plays or is muted.
            .overlay(alignment: .bottomTrailing) {
                if !magnified {
                    TabAudioButton(tab: tab, colors: colors, commands: commands)
                        .background { if tab.isMuted || tab.isPlayingAudio { Circle().fill(colors.panel) } }
                        .offset(x: 5, y: 3)
                }
            }
            .tabPeek(tab, commands: commands)
            .contextMenu { TabContextMenu(tab: tab, state: state, commands: commands) }
    }
}

/// A list tile's faint fill under the pointer (the list takes its clicks, so there is no pressed state).
private struct RailTileHover: ViewModifier {
    let colors: Palette
    var quiet = false
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(colors.text.opacity(quiet || !hovering ? 0 : 0.06)))
            .sidebarHover($hovering)
            .animation(.easeOut(duration: hovering ? 0.1 : 0.2), value: hovering)
    }
}

/// A faint fill under the pointer, deeper while pressed.
private struct RailButtonStyle: ButtonStyle {
    let colors: Palette
    /// Magnify's copy draws no fill: the rail's own tile under it does.
    var quiet = false
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                .fill(colors.text.opacity(quiet ? 0 : configuration.isPressed ? 0.12 : hovering ? 0.06 : 0)))
            .sidebarHover($hovering)
            .animation(.easeOut(duration: hovering ? 0.1 : 0.2), value: hovering)
    }
}

/// The new-tab tile grows and gets its row like the tabs under Magnify.
private struct RailNewTabMagnify: ViewModifier {
    let magnifies: Bool
    func body(content: Content) -> some View {
        if magnifies { content.railMagnify(.newTab, iconSize: 14) } else { content }
    }
}

/// The full sidebar's close button for a tab row.
struct RailTabCloseButton: View {
    let tab: TabItem
    let colors: Palette
    weak var commands: BrowserCommands?

    var body: some View {
        Button { withAnimation(.ikago) { commands?.closeTab(tab.id) } } label: {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .frame(width: 20, height: 20)
                .background(Circle().fill(colors.hover.opacity(1.5)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(colors.secondary)
        .help("Close Tab (⌘W)")
        .accessibilityLabel("Close \(tab.displayTitle)")
        .transition(.opacity.combined(with: .scale(scale: 0.7)))
    }
}

/// Tells the hover effects where the rail's own buttons are (window coordinates from the top), so their overlay always
/// lets clicks through to them (`RailHoverModel.reportButton`).
private struct RailButtonArea: ViewModifier {
    let key: String
    let model: RailHoverModel
    let reports: Bool
    @State private var id = UUID()

    func body(content: Content) -> some View {
        if reports {
            content
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { model.reportButton(key + id.uuidString, frame: $0) }
                .onDisappear { model.reportButton(key + id.uuidString, frame: nil) }
        } else {
            content
        }
    }
}
