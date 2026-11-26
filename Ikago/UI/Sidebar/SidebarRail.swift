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
    @Namespace private var selection
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
            Color.clear.frame(height: state.showsSidebarTopTabs ? 4 : state.sidebarOnRight && !state.sidebarLightsFollow ? 10 : Self.lightsHeight)
            // The sidebar button sits where the full sidebar has it: at the top when its top row holds it.
            if toggleOnTop {
                sidebarToggle(colors)
                    .padding(.leading, Self.tileInset)
                    .opacity(magnified ? 0 : 1)
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
            // The full sidebar's order: pinned tabs, groups, a line, New Tab, then the tabs.
            SidebarScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    // Top Tabs can keep groups in the tab row only (Settings ▸ Appearance ▸ Tab Groups).
                    if !state.showsPinnedGrid && !state.showsSidebarTopTabs {
                        ForEach(state.pinnedTabs) { tab in tabTile(tab, colors: colors) }
                    }
                    // Pinned groups sit with the pins, whatever the group placement: a tile each with a menu of its tabs.
                    if !magnified {
                        ForEach(state.pinnedFolders) { folder in
                            PinnedGroupTile(folder: folder, state: state, chrome: chrome, commands: commands)
                        }
                    }
                    if state.showsGroupsInSidebar {
                        // Groups in the block; under Top Tabs (no loose tabs here) the ones placed among tabs follow them.
                        ForEach(state.showsSidebarTopTabs ? state.listedFolders : state.blockFolders) { folder in group(folder, colors: colors) }
                    }
                    if !state.showsSidebarTopTabs {
                        if state.chromeLayout.sidebarShowsNewTab {
                            if hasItemsAboveNewTab {
                                Capsule().fill(colors.separator).frame(width: 20, height: 1).frame(width: 36)
                                    .padding(.vertical, 4)
                                    .opacity(magnified ? 0 : 1)
                            }
                            tile(symbol: "plus", label: "New Tab", colors: colors) { commands?.newTab() }
                        }
                        ForEach(state.looseTabs) { tab in tabTile(tab, colors: colors) }
                        // Below the last tile: a tab dropped here goes last; a group leaves the group it was in.
                        if !magnified {
                            Color.clear.frame(width: 36, height: 44).tabListEndDrop(state: state, chrome: chrome)
                        }
                    }
                }
                .padding(.vertical, 2)
                .padding(.leading, Self.tileInset)
                .frame(maxWidth: .infinity, alignment: .leading)
                .railSpace(surface.list) { model.listScrolled(surface.list) }
                // The rows live in the scroll view's own host: an animation set out here never reaches them.
                .animation(reduceMotion ? nil : .ikagoQuick, value: state.listedFolders.map { $0.id + "@" + ($0.afterTabID ?? "-") })
            }
            .frame(maxHeight: .infinity)
            // The foot stays a column of icons, wider or not.
            Group {
                if state.spaces.count > 1 { spaces(colors) }
                ForEach(footItems) { item in
                    if item == .sidebarToggle {
                        sidebarToggle(colors)
                    } else {
                        ChromeItemView(item: item, state: state, colors: colors, commands: commands, size: 32)
                    }
                }
            }
            .opacity(magnified ? 0 : 1)
            .frame(width: BrowserState.sidebarRailWidth)
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
        !state.pinnedTabs.isEmpty || !state.pinnedFolders.isEmpty || (state.showsGroupsInSidebar && !state.blockFolders.isEmpty)
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
            && (layout.topLeading + layout.topCenter + layout.sidebarTop).contains(.sidebarToggle)
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

    @ViewBuilder private func group(_ folder: TabFolder, colors: Palette) -> some View {
        let tabs = state.tabs(inSubtree: folder)
        let hidden = folder.isClosed == true
        let open = folder.isOpen && !hidden
        let tint = folder.tagValue?.color ?? colors.secondary
        VStack(spacing: 0) {
            // The same open state as the full sidebar's group, so switching between them keeps it.
            // A hidden group shows faded with a mark; a click brings it back with its tabs.
            Button {
                if hidden { state.reopenFolder(folder.id) } else { state.toggleFolder(folder.id) }
            } label: {
                railIcon(folder.name, colors: colors) {
                    FolderIcon(folder: folder, colors: colors, size: 15)
                    .railMagnify(.folder(folder.id), iconSize: 15)
                    .opacity(hidden ? 0.35 : TabListView.isSleeping(tabs, activeID: state.activeTabID) && !open ? 0.45 : 1)
                    .overlay(alignment: .topTrailing) {
                        if hidden && !magnified {
                            Image(systemName: "eye.slash.fill").font(.system(size: 7.5, weight: .bold))
                                .foregroundStyle(colors.secondary).offset(x: 8, y: -7)
                        }
                    }
                    .frame(width: 36, height: 36)
                    .overlay(alignment: .bottomTrailing) {
                        // How many tabs it holds, as a small badge that never covers the icon (Settings ▸ Show tab counts).
                        if state.showsGroupTabCounts && !hidden && !magnified { badge(tabs.count, colors: colors, open: open) }
                    }
                }
                .frame(height: 36)
                .background {
                    // An active tab hidden in a closed group still shows where it is.
                    if !open, !magnified, tabs.contains(where: { $0.id == state.activeTabID }) {
                        RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(colors.selected)
                            .matchedGeometryEffect(id: "rail-active", in: selection)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
            }
            .buttonStyle(RailButtonStyle(colors: colors, quiet: magnified))
            .help(effect != nil ? "" : hidden ? "\(folder.name) · hidden — click to show" : "\(folder.name) · \(tabs.count) \(tabs.count == 1 ? "tab" : "tabs")")
            .contextMenu { FolderContextMenu(folder: folder, state: state, commands: commands) }
            // Dragged like the full sidebar's group headers: tabs dropped on it join the group; groups go before,
            // into or after it.
            .modifier(RailGroupDrag(folder: folder, state: state, chrome: chrome, colors: colors))
            // Opens and closes like the full sidebar's groups: the rows' measured height grows on the same spring and
            // the clip reveals them, so the tiles below move with it.
            RailDisclosure(isOpen: open) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(tabs) { tab in tabTile(tab, colors: colors) }
                }
                .padding(.top, 4).padding(.bottom, 3)
            }
        }
        // The open group's tint sits behind the tile and its tabs; it never takes clicks (it used to cover the tile, so
        // a group opened but couldn't be closed).
        .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(tint.opacity(0.12))
            .opacity(open && !magnified ? 1 : 0).allowsHitTesting(false))
        .animation(reduceMotion ? nil : .groupDisclosure, value: open)
    }

    private func badge(_ count: Int, colors: Palette, open: Bool) -> some View {
        Text("\(count)")
            .font(.system(size: 8.5, weight: .bold).monospacedDigit())
            .foregroundStyle(colors.secondary)
            .padding(.horizontal, 3.5).frame(minWidth: 13, minHeight: 13)
            .background(Capsule().fill(colors.text.opacity(0.08)))
            .offset(x: 1, y: 1)
            .opacity(open ? 0 : 1)
    }

    // MARK: Tiles

    private func tabTile(_ tab: TabItem, colors: Palette, essential: Bool = false) -> some View {
        let active = tab.id == state.activeTabID
        return Button { if NSEvent.modifierFlags.contains(.option) { commands?.peekTab(tab.id) } else { state.select(tab.id) } } label: {
            railIcon(tab.displayTitle, colors: colors) {
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
                    if active && !magnified {
                        RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(colors.selected)
                            .matchedGeometryEffect(id: "rail-active", in: selection)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
        }
        .buttonStyle(RailButtonStyle(colors: colors, quiet: magnified))
        // A mute badge on the tile while it plays or is muted.
        .overlay(alignment: .bottomTrailing) {
            if !magnified { audio(tab, colors: colors) }
        }
        .tabPeek(tab, commands: commands)
        .contextMenu { TabContextMenu(tab: tab, state: state, commands: commands) }
        // The full sidebar's drags: reorder among the tiles, into a group, onto the page to split it, or out of the
        // window into a new one.
        .onDrag {
            chrome.beginTabDrag(tab.id)
            return TabDrag.provider(tab.id)
        } preview: {
            TabDragPreview(tab: tab, colors: colors, count: chrome.selectedTabIDs.contains(tab.id) ? chrome.selectedTabIDs.count : 1)
        }
        .tabDropTarget(tab, axis: .vertical, state: state, chrome: chrome)
    }

    private func audio(_ tab: TabItem, colors: Palette) -> some View {
            TabAudioButton(tab: tab, colors: colors, commands: commands)
                .background { if tab.isMuted || tab.isPlayingAudio { Circle().fill(colors.panel) } }
                .offset(x: 5, y: 3)
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

/// A rail group's tiles, opened and closed like the full sidebar's rows (`SidebarFolderSection`): mounted shut first so
/// their height is known, then only the frame's height animates on `Animation.groupDisclosure` while the clip reveals them.
private struct RailDisclosure<Content: View>: View {
    let isOpen: Bool
    @ViewBuilder let content: Content
    @State private var open: Bool?
    @State private var mounted = false
    @State private var height: CGFloat?
    @State private var closing: DispatchWorkItem?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shown = open ?? isOpen
        Group {
            if mounted || shown {
                content
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
                    .frame(height: shown ? height : 0, alignment: .top)
                    .clipped()
                    .opacity(shown ? 1 : 0)
                    // Shut, its tiles are not under the pointer (`railMagnify`).
                    .environment(\.railItemsHidden, !shown)
            }
        }
        .onAppear { if open == nil { open = isOpen; mounted = isOpen } }
        .onChange(of: isOpen) { _, now in set(now) }
    }

    private func set(_ now: Bool) {
        closing?.cancel()
        let animation: Animation? = reduceMotion ? nil : .groupDisclosure
        if now {
            if !mounted {
                mounted = true
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { open = false }
                DispatchQueue.main.async { withAnimation(animation) { open = true } }
            } else {
                withAnimation(animation) { open = true }
            }
        } else {
            withAnimation(animation) { open = false }
            let work = DispatchWorkItem { mounted = false }
            closing = work
            DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0 : Animation.groupDisclosureDuration * 1.6), execute: work)
        }
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

/// A rail group tile as a drag source and target, like the full sidebar's group header (`SidebarFolderSection`).
private struct RailGroupDrag: ViewModifier {
    let folder: TabFolder
    let state: BrowserState
    let chrome: ChromeModel
    let colors: Palette
    @State private var targeted = false
    @State private var zone: GroupDropZone?
    @State private var height = MeasuredLength(36)

    func body(content: Content) -> some View {
        content
            .overlay {
                if targeted {
                    RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                        .strokeBorder(folder.tagValue?.color ?? colors.accent, lineWidth: 1.5)
                }
            }
            .overlay(alignment: zone == .after ? .bottom : .top) {
                if zone == .before || zone == .after { GroupInsertionLine(colors: colors).offset(y: zone == .after ? 1 : -1) }
            }
            .opacity(chrome.draggingFolderID == folder.id ? 0.5 : 1)
            .onDrag {
                chrome.beginFolderDrag(folder.id)
                return GroupDrag.provider(folder.id)
            } preview: {
                GroupDragPreview(folder: folder, colors: colors)
            }
            .onDrop(of: [.ikagoTab, .ikagoGroup], delegate: FolderHeaderDropDelegate(
                folder: folder, state: state, chrome: chrome, length: height, tabTargeted: $targeted, zone: $zone))
            .onChange(of: chrome.draggingFolderID) { _, id in if id == nil { zone = nil } }
            .animation(.ikagoQuick, value: targeted)
            .animation(.ikagoQuick, value: zone)
    }
}
