import SwiftUI

/// The Sidebar layout's middle state: a slim rail of icons beside the page. The traffic lights stand in a
/// column at the top (Ikago draws them there, `FullScreenWindowControls`), then the essentials (pinned tabs)
/// as tiles, a new-tab button, groups as one tile each (their icon in their colour; a click opens them in place), loose tabs, and at the bottom the Spaces and the sidebar button, which
/// moves on to the next sidebar state. Titles show on hover; the active tab's highlight slides between tiles.
struct SidebarRail: View {
    let state: BrowserState
    weak var commands: BrowserCommands?
    @Namespace private var selection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Room for the three traffic lights in a column.
    static let lightsHeight: CGFloat = 78

    var body: some View {
        let colors = state.palette
        VStack(spacing: 8) {
            // Under the Sidebar + Tabs row the lights stay in that row, beside the tabs.
            Color.clear.frame(height: state.showsSidebarTopTabs ? 4 : state.sidebarOnRight && !state.sidebarLightsFollow ? 10 : Self.lightsHeight)
            if !state.pinnedTabs.isEmpty {
                VStack(spacing: 6) {
                    ForEach(state.pinnedTabs) { tab in tabTile(tab, colors: colors, essential: true) }
                }
            }
            // Sidebar + Tabs: loose tabs and the + live in the tab row; the rail keeps pins and groups.
            if !state.showsSidebarTopTabs {
                tile(symbol: "plus", label: "New Tab", colors: colors) { commands?.newTab() }
            }
            if !state.pinnedTabs.isEmpty || !state.showsSidebarTopTabs {
                Capsule().fill(colors.separator).frame(width: 20, height: 1)
            }
            SidebarScrollView {
                VStack(spacing: 4) {
                    ForEach(state.childFolders(of: nil)) { folder in group(folder, colors: colors) }
                    if !state.showsSidebarTopTabs {
                        ForEach(state.looseTabs) { tab in tabTile(tab, colors: colors) }
                    }
                }
                .padding(.vertical, 2)
                // The rows live in the scroll view's own host: an animation set out here never reaches them.
                .animation(reduceMotion ? nil : .ikagoQuick, value: state.childFolders(of: nil).map(\.id))
            }
            .frame(maxHeight: .infinity)
            if state.spaces.count > 1 { spaces(colors) }
            tile(symbol: "sidebar.left", label: "Hide Sidebar", colors: colors) { commands?.cycleSidebar() }
        }
        .padding(.bottom, 10)
        .frame(width: BrowserState.sidebarRailWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(SidebarSpaceSwipe(state: state))
        .background(WindowDragArea())
        .ignoresSafeArea(.container, edges: .top)
        .animation(.ikagoQuick, value: state.activeTabID)
    }

    // MARK: Groups

    @ViewBuilder private func group(_ folder: TabFolder, colors: Palette) -> some View {
        let tabs = state.tabs(inSubtree: folder)
        let open = folder.isOpen
        let tint = folder.tagValue?.color ?? colors.secondary
        VStack(spacing: 0) {
            // The same open state as the full sidebar's group, so switching between them keeps it.
            Button { state.toggleFolder(folder.id) } label: {
                FolderIcon(folder: folder, colors: colors, size: 15)
                .opacity(TabListView.isSleeping(tabs, activeID: state.activeTabID) && !open ? 0.45 : 1)
                .frame(width: 36, height: 36)
                .background {
                    // An active tab hidden in a closed group still shows where it is.
                    if !open, tabs.contains(where: { $0.id == state.activeTabID }) {
                        RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(colors.selected)
                            .matchedGeometryEffect(id: "rail-active", in: selection)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    // How many tabs it holds, as a small badge that never covers the icon (Settings ▸ Show tab counts).
                    if state.showsGroupTabCounts { badge(tabs.count, colors: colors, open: open) }
                }
                .contentShape(RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
            }
            .buttonStyle(RailButtonStyle(colors: colors))
            .help("\(folder.name) · \(tabs.count) \(tabs.count == 1 ? "tab" : "tabs")")
            // Opens and closes like the full sidebar's groups: the rows' measured height grows on the same spring and
            // the clip reveals them, so the tiles below move with it.
            RailDisclosure(isOpen: open) {
                VStack(spacing: 4) {
                    ForEach(tabs) { tab in tabTile(tab, colors: colors) }
                }
                .padding(.top, 4).padding(.bottom, 3)
            }
        }
        // The open group's tint sits behind the tile and its tabs; it never takes clicks (it used to cover the tile, so
        // a group opened but couldn't be closed).
        .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(tint.opacity(0.12))
            .opacity(open ? 1 : 0).allowsHitTesting(false))
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
            FaviconView(tab: tab, size: essential ? 18 : 16)
                .opacity(tab.isUnloaded && !active ? 0.55 : 1)
                .frame(width: 36, height: 36)
                .background {
                    if essential && !colors.glass {
                        RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(colors.text.opacity(0.06))
                    }
                }
                // Essentials are glass tiles with Liquid Glass on, like the sidebar's pinned grid.
                .glassControl(RoundedRectangle(cornerRadius: Radius.row, style: .continuous), colors, active: essential)
                .background {
                    if active {
                        RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(colors.selected)
                            .matchedGeometryEffect(id: "rail-active", in: selection)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
        }
        .buttonStyle(RailButtonStyle(colors: colors))
        .overlay(alignment: .bottomTrailing) {
            TabAudioButton(tab: tab, colors: colors, commands: commands)
                .background { if tab.isMuted || tab.isPlayingAudio { Circle().fill(colors.panel) } }
                .offset(x: 5, y: 3)
        }
        .tabPeek(tab, commands: commands)
        .contextMenu { TabContextMenu(tab: tab, state: state, commands: commands) }
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

    private func tile(symbol: String, label: String, colors: Palette, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(colors.secondary)
                .frame(width: 36, height: 32)
                .contentShape(RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
                .glassControl(RoundedRectangle(cornerRadius: Radius.row, style: .continuous), colors)
        }
        .buttonStyle(RailButtonStyle(colors: colors))
        .help(label)
        .accessibilityLabel(label)
    }
}

/// A faint fill under the pointer, deeper while pressed.
private struct RailButtonStyle: ButtonStyle {
    let colors: Palette
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                .fill(colors.text.opacity(configuration.isPressed ? 0.12 : hovering ? 0.06 : 0)))
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
