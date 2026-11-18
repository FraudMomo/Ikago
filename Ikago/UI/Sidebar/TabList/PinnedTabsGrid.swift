import SwiftUI

// MARK: - Pinned tabs grid
/// Pinned tabs as tiles at the top of the sidebar.
struct PinnedTabsGrid: View {
    let state: BrowserState
    let chrome: ChromeModel
    weak var commands: BrowserCommands?
    var onSelection: (() -> Void)? = nil
    var columnCount = 3

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selection
    @State private var hoveredID: String?
    @Environment(\.sidebarScrolling) private var scrolling
    private var columns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: 8), count: columnCount) }

    var body: some View {
        let colors = state.palette
        LazyVGrid(columns: columns, spacing: 8) {
                ForEach(state.sidebarGridPinnedTabs) { tab in
                    let active = tab.id == state.activeTabID
                    Button { TabClick.handle(tab, state: state, chrome: chrome, commands: commands) { withAnimation(.ikago) { state.select(tab.id) }; onSelection?() } } label: {
                        FaviconView(tab: tab, size: 18)
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .bottomTrailing) {
                        TabAudioButton(tab: tab, colors: colors, commands: commands)
                            .background { if tab.isMuted || tab.isPlayingAudio { Circle().fill(colors.panel) } }
                            .padding(2)
                    }
                    .background {
                        RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                            .fill(hoveredID == tab.id ? colors.hover.opacity(2) : colors.glass ? .clear : colors.hover)
                            .animation(reduceMotion ? nil : .easeOut(duration: hoveredID == tab.id ? 0.1 : 0.2), value: hoveredID == tab.id)
                        TabSelectionHighlight(shape: RoundedRectangle(cornerRadius: Radius.card, style: .continuous), active: active,
                                              color: colors.selected, selection: selection, id: "pinned-active")
                    }
                    // Glass tiles with Liquid Glass on, like every other control in the sidebar.
                    .glassControl(RoundedRectangle(cornerRadius: Radius.card, style: .continuous), colors, reacts: false)
                    .onHover { inside in
                        guard !scrolling, chrome.coversTabs == false || !inside else { return }
                        if inside { hoveredID = tab.id }
                        else if hoveredID == tab.id { hoveredID = nil }
                    }
                    .onChange(of: scrolling) { _, now in if now, hoveredID == tab.id { hoveredID = nil } }
                    .onChange(of: chrome.coversTabs) { _, now in if now, hoveredID == tab.id { hoveredID = nil } }
                    .opacity(tab.isUnloaded ? 0.48 : 1)
                    .tabPeek(tab, commands: commands)
                    .contextMenu { TabContextMenu(tab: tab, state: state, commands: commands) }
                    .onMiddleClick { withAnimation(.ikago) { commands?.closeTab(tab.id) } }
                    .onDrag {
                        chrome.beginTabDrag(tab.id)
                        return TabDrag.provider(tab.id)
                    }
                    .tabDropTarget(tab, axis: .horizontal, state: state, chrome: chrome)
                }
            }
        .animation(reduceMotion ? nil : .ikagoQuick, value: state.sidebarGridPinnedTabs.map(\.id))
        .onDisappear { hoveredID = nil }
    }
}

/// Shared right-click menu for tab rows and pinned tiles.
struct TabContextMenu: View {
    let tab: TabItem
    let state: BrowserState
    weak var commands: BrowserCommands?

    var body: some View {
        let selection = commands?.tabSelection(including: tab.id) ?? [tab.id]
        if selection.count > 1 { SelectedTabsMenu(ids: selection, state: state, commands: commands) } else { single }
    }

    @ViewBuilder private var single: some View {
        Button(tab.pinned ? "Unpin Tab" : "Pin Tab") { withAnimation(.ikagoQuick) { state.togglePin(tab.id) } }
        Button(tab.isMuted ? "Unmute Tab" : "Mute Tab") { commands?.toggleMute(tab.id) }
        if let group = state.splitGroup(of: tab.id) {
            Button("Remove from Split") { withAnimation(.ikago) { state.separate(tab.id) } }
            Button("Separate All Tabs") { withAnimation(.ikago) { state.unsplitGroup(containing: group[0]) } }
        } else if tab.id != state.activeTabID {
            Button("Open in Split View") { withAnimation(.ikago) { commands?.splitWith(tab.id) } }
        }
        Button("Copy Address") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(tab.url, forType: .string)
        }
        Button("Duplicate Tab") { state.newTab(url: tab.url, after: tab.id) }
        if !state.isPrivate {
            Button("Move to New Window") { commands?.moveToNewWindow(tab.id) }.disabled(state.tabs.count < 2)
        }
        if AddressResolver.isWebURL(tab.url) {
            Button("Open in Private Window") { commands?.openInPrivateWindow(tab.url) }
        }
        if !tab.pinned {
            Menu("Move to Group") {
                ForEach(state.orderedSpaceFolders.filter { $0.id != tab.folderID }) { folder in
                    Button(folder.name) { state.moveToFolder(tab.id, folderID: folder.id) }
                }
                Button("New Group…") { commands?.newFolder(with: tab.id) }
            }
            if tab.folderID != nil {
                Button("Remove from Group") { state.moveToFolder(tab.id, folderID: nil) }
            }
        }
        if state.spaces.count > 1 {
            Menu("Move to Space") {
                ForEach(state.spaces.filter { $0.id != tab.spaceID }) { space in
                    Button { withAnimation(.ikago) { state.moveTab(tab.id, toSpace: space.id) } } label: {
                        Label(space.name, systemImage: space.symbol)
                    }
                }
            }
        }
        Divider()
        if !tab.isUnloaded {
            Button("Unload Tab") { commands?.unloadTab(tab.id) }
        }
        Button(tab.pinned ? "Unload Pinned Tab — Keep Pin" : "Close Tab") { commands?.closeTab(tab.id) }
    }
}

/// The menu for several selected tabs (`TabClick`): everything acts on all of them.
private struct SelectedTabsMenu: View {
    let ids: [String]
    let state: BrowserState
    weak var commands: BrowserCommands?

    var body: some View {
        Button("Move \(ids.count) Tabs to New Window") { commands?.moveTabsToNewWindow(ids) }
            .disabled(state.isPrivate || ids.count >= state.tabs.count)
        Button("New Group with \(ids.count) Tabs…") { commands?.newFolder(withTabs: ids) }
        Menu("Move \(ids.count) Tabs to Group") {
            ForEach(state.orderedSpaceFolders) { folder in
                Button(folder.name) { withAnimation(.ikago) { commands?.moveTabs(ids, toFolder: folder.id) } }
            }
            Button("Remove from Group") { withAnimation(.ikago) { commands?.moveTabs(ids, toFolder: nil) } }
        }
        if state.spaces.count > 1 {
            Menu("Move \(ids.count) Tabs to Space") {
                ForEach(state.spaces.filter { $0.id != state.activeSpaceID }) { space in
                    Button { withAnimation(.ikago) { state.moveTabs(ids, toSpace: space.id) } } label: {
                        Label(space.name, systemImage: space.symbol)
                    }
                }
            }
        }
        Divider()
        Button("Close \(ids.count) Tabs") { withAnimation(.ikago) { commands?.closeTabs(ids) } }
    }
}

// MARK: - Pin boundary
/// A drop line between sections that takes no room in the list: the target hangs over the gap between groups,
/// so groups keep their usual spacing and nothing moves when a drag starts.
struct SidebarPinBoundary: View {
    let state: BrowserState
    let chrome: ChromeModel
    let afterFolderID: String?
    @State private var targeted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Color.clear.frame(height: 0).overlay {
            Capsule().fill(state.palette.accent.opacity(targeted ? 0.85 : 0))
                .frame(height: 2).padding(.horizontal, 10).frame(height: 8)
                .contentShape(Rectangle())
                .onDrop(of: [.ikagoTab], isTargeted: $targeted) { providers in
                    guard let provider = providers.first else { return false }
                    TabDrag.load(provider, into: state) { id in
                        withAnimation(reduceMotion ? nil : .ikagoQuick) {
                            state.movePin(id, intoGrid: false, afterFolderID: afterFolderID)
                        }
                        chrome.endTabDrag()
                    }
                    return true
                }
        }
        .animation(reduceMotion ? nil : .ikagoQuick, value: targeted)
        .recordLayout("sidebar-pin-boundary-\(afterFolderID ?? "top")")
        .accessibilityLabel(afterFolderID == nil ? "Pin above groups" : "Pin after group")
    }
}
