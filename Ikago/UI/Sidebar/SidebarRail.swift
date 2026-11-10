import SwiftUI

/// The Sidebar layout's middle state: a slim rail of icons beside the page. The traffic lights stand in a
/// column at the top (Ikago draws them there, `FullScreenWindowControls`), then the essentials (pinned tabs)
/// as tiles, a new-tab button, groups as one tile each (their icon in their colour; a click opens them in place), loose tabs, and at the bottom the Spaces and the sidebar button, which
/// moves on to the next sidebar state. Titles show on hover; the active tab's highlight slides between tiles.
struct SidebarRail: View {
    let state: BrowserState
    weak var commands: BrowserCommands?
    @Namespace private var selection
    @State private var openGroups: Set<String> = []

    /// Room for the three traffic lights in a column.
    static let lightsHeight: CGFloat = 78

    var body: some View {
        let colors = state.palette
        VStack(spacing: 8) {
            Color.clear.frame(height: Self.lightsHeight)
            if !state.pinnedTabs.isEmpty {
                VStack(spacing: 6) {
                    ForEach(state.pinnedTabs) { tab in tabTile(tab, colors: colors, essential: true) }
                }
            }
            tile(symbol: "plus", label: "New Tab", colors: colors) { commands?.newTab() }
            Capsule().fill(colors.separator).frame(width: 20, height: 1)
            SidebarScrollView {
                VStack(spacing: 4) {
                    ForEach(state.spaceFolders) { folder in group(folder, colors: colors) }
                    ForEach(state.looseTabs) { tab in tabTile(tab, colors: colors) }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: .infinity)
            if state.spaces.count > 1 { spaces(colors) }
            tile(symbol: "sidebar.left", label: "Hide Sidebar", colors: colors) { commands?.cycleSidebar() }
        }
        .padding(.bottom, 10)
        .frame(width: BrowserState.sidebarRailWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(WindowDragArea())
        .ignoresSafeArea(.container, edges: .top)
        .animation(.ikagoQuick, value: state.activeTabID)
        .animation(.ikago, value: openGroups)
    }

    // MARK: Groups

    @ViewBuilder private func group(_ folder: TabFolder, colors: Palette) -> some View {
        let tabs = state.tabs(in: folder)
        let open = openGroups.contains(folder.id)
        let tint = folder.tagValue?.color ?? colors.secondary
        VStack(spacing: 4) {
            Button {
                if open { openGroups.remove(folder.id) } else { openGroups.insert(folder.id) }
            } label: {
                FolderIcon(folder: folder, colors: colors, size: 15)
                .frame(width: 36, height: 36)
                .background {
                    // An active tab hidden in a closed group still shows where it is.
                    if !open, tabs.contains(where: { $0.id == state.activeTabID }) {
                        RoundedRectangle(cornerRadius: 10, style: .continuous).fill(colors.selected)
                            .matchedGeometryEffect(id: "rail-active", in: selection)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    Text("\(tabs.count)")
                        .font(.system(size: 8, weight: .semibold).monospacedDigit())
                        .foregroundStyle(colors.secondary)
                        .padding(3)
                }
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(RailButtonStyle(colors: colors))
            .help(folder.name)
            if open {
                VStack(spacing: 4) {
                    ForEach(tabs) { tab in tabTile(tab, colors: colors) }
                }
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.opacity(0.12)))
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
        }
    }

    // MARK: Tiles

    private func tabTile(_ tab: TabItem, colors: Palette, essential: Bool = false) -> some View {
        let active = tab.id == state.activeTabID
        return Button { state.select(tab.id) } label: {
            FaviconView(tab: tab, size: essential ? 18 : 16)
                .opacity(tab.isHibernating && !active ? 0.55 : 1)
                .frame(width: 36, height: 36)
                .background {
                    if essential {
                        RoundedRectangle(cornerRadius: 10, style: .continuous).fill(colors.text.opacity(0.06))
                    }
                }
                .background {
                    if active {
                        RoundedRectangle(cornerRadius: 10, style: .continuous).fill(colors.selected)
                            .matchedGeometryEffect(id: "rail-active", in: selection)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(RailButtonStyle(colors: colors))
        .overlay(alignment: .bottomTrailing) {
            TabAudioButton(tab: tab, colors: colors, commands: commands)
                .background { if tab.isMuted || tab.isPlayingAudio { Circle().fill(colors.panel) } }
                .offset(x: 5, y: 3)
        }
        .help(tab.title.isEmpty ? tab.url : tab.title)
        .contextMenu {
            Button(tab.pinned ? "Unpin Tab" : "Pin Tab") { state.togglePin(tab.id) }
            Button("Close Tab") { commands?.closeTab(tab.id) }
        }
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
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(colors.text.opacity(configuration.isPressed ? 0.12 : hovering ? 0.06 : 0)))
            .sidebarHover($hovering)
            .animation(.easeOut(duration: hovering ? 0.1 : 0.2), value: hovering)
    }
}
