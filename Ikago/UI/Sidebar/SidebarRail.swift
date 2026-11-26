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
    /// Expand's wider rail (`RailHover`): the same items in the same places, each with its name beside its icon. Drawn
    /// over the rail and the page by `RailExpandPanel`, never in the dock.
    var expanded = false
    /// Magnify's copy of the rail (`RailMagnifyLayer`): only the icons, in the same places, growing in the carousel; drawn
    /// over the rail, whose tiles stay and whose own icons step aside, so the rows can lie between the tiles and icons.
    var magnified = false
    /// One of the copies drawn over the rail by the hover effects, not the rail in the window.
    private var isCopy: Bool { expanded || magnified }
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
        // Leading-aligned, with every item in the rail's 64 pt column (tiles 14 pt in), so the wider rail keeps each icon
        // exactly where the rail has it and only the names grow out.
        VStack(alignment: .leading, spacing: 8) {
            // Under the Top Tabs row the lights stay in that row, beside the tabs.
            Color.clear.frame(height: state.showsSidebarTopTabs ? 4 : state.sidebarOnRight && !state.sidebarLightsFollow ? 10 : Self.lightsHeight)
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
                        // The tabs, with the groups placed among them.
                        ForEach(state.looseEntries) { entry in
                            switch entry {
                            case .tab(let tab): tabTile(tab, colors: colors)
                            case .folder(let folder): if state.showsGroupsInSidebar { group(folder, colors: colors) }
                            }
                        }
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
                        tile(symbol: "sidebar.left", label: "Hide Sidebar", colors: colors, named: false) { commands?.cycleSidebar() }
                    } else {
                        ChromeItemView(item: item, state: state, colors: colors, commands: commands, size: 32)
                    }
                }
            }
            .opacity(magnified ? 0 : 1)
            .frame(width: BrowserState.sidebarRailWidth)
        }
        .padding(.bottom, 10)
        // While the wider rail lies over this one, this one's items step aside: through a see-through material they
        // would show twice. (Not 0: SwiftUI stops hit-testing a view it no longer draws.)
        .opacity(!isCopy && model.covered && model.effect == .expand && model.surface === surface ? 0.001 : 1)
        .animation(nil, value: model.covered)
        .frame(width: width, alignment: .leading)
        .railSpace(surface.rail)
        .environment(\.railHover, effect == .magnify && !expanded ? model : nil)
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
    private var width: CGFloat { expanded ? RailHover.expandedWidth : BrowserState.sidebarRailWidth }
    /// A row's width: the tile, or with the rail wider the tile and its name, up to the same inset from the far edge.
    private var rowWidth: CGFloat { expanded ? RailHover.expandedWidth - 2 * Self.tileInset : 36 }

    /// The hover effect in use: none under Reduce Motion.
    private var effect: RailHoverEffect? {
        reduceMotion ? nil : state.browserPreferences.railHover
    }

    /// The controls at the rail's foot (Settings ▸ Sidebar & Toolbar ▸ Customize ▸ Icons-only sidebar). Downloads join
    /// them while there are any, unless a toolbar above the page already shows them.
    private var footItems: [ChromeItem] {
        var items = state.visibleChromeItems(state.chromeLayout.rail).filter { $0 != .spaces || state.spaces.count < 2 }
        if !state.usesTabsLayout, !items.contains(.downloads), DownloadCenter.shared.showsToolbarButton { items.append(.downloads) }
        if state.addsTabGroupsButton(in: .rail) { items.append(.tabGroups) }
        return items
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
        // The wider rail's rows have the full sidebar's controls at their end; the rail's tiles a mute badge.
        .modifier(RailTabControls(tab: tab, colors: colors, commands: commands, inRow: expanded))
        .overlay(alignment: .bottomTrailing) {
            if !magnified && !expanded { audio(tab, colors: colors) }
        }
        .tabPeek(tab, commands: commands)
        .contextMenu { TabContextMenu(tab: tab, state: state, commands: commands) }
    }

    private func audio(_ tab: TabItem, colors: Palette) -> some View {
            TabAudioButton(tab: tab, colors: colors, commands: commands)
                .background { if tab.isMuted || tab.isPlayingAudio { Circle().fill(colors.panel) } }
                .offset(x: 5, y: 3)
    }

    /// A tile's icon in its 36 pt box, and in the wider rail its name beside it (Magnify shows it in its tab row
    /// instead: `RailMagnifyRow`).
    private func railIcon<Icon: View>(_ name: String? = nil, colors: Palette, @ViewBuilder _ icon: () -> Icon) -> some View {
        HStack(spacing: 2) {
            icon().frame(width: 36)
            if expanded, let name {
                Text(name).font(.system(size: 13)).foregroundStyle(colors.text).lineLimit(1)
                    .fadeTruncated()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Room for a tab row's controls at its end (`RailTabControls`).
                    .padding(.trailing, 26)
            }
        }
        .frame(width: name == nil ? 36 : rowWidth, alignment: .leading)
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
    /// The whole row is under the pointer, its controls included (`RailTabControls`).
    @Environment(\.railRowHovered) private var rowHovered

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                .fill(colors.text.opacity(quiet ? 0 : configuration.isPressed ? 0.12 : hovering || rowHovered ? 0.06 : 0)))
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

/// A tab row's controls at its end, as in the full sidebar: camera, microphone and sound while in use, and a close
/// button while the pointer is on the row. Beside the row's own button, never inside it, so each takes its own clicks.
private struct RailTabControls: ViewModifier {
    let tab: TabItem
    let colors: Palette
    weak var commands: BrowserCommands?
    let inRow: Bool
    @State private var hovering = false

    func body(content: Content) -> some View {
        if inRow {
            // The row's hover covers its controls too: tracked on the button alone, moving onto the close button left
            // the row, which hid the button and its highlight, and they flickered as the pointer moved.
            content
                .environment(\.railRowHovered, hovering)
                .overlay(alignment: .trailing) {
                    HStack(spacing: 4) {
                        TabMediaIndicators(tab: tab, colors: colors, commands: commands)
                        if hovering { RailTabCloseButton(tab: tab, colors: colors, commands: commands) }
                    }
                    .padding(.trailing, 7)
                }
                .sidebarHover($hovering)
                .animation(.ikagoQuick, value: hovering)
        } else {
            content
        }
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

private struct RailRowHoveredKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// A wider rail's row is under the pointer, its controls included.
    fileprivate var railRowHovered: Bool {
        get { self[RailRowHoveredKey.self] }
        set { self[RailRowHoveredKey.self] = newValue }
    }
}
