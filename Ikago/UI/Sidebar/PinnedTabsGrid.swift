import SwiftUI

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
                ForEach(state.pinnedTabs) { tab in
                    let active = tab.id == state.activeTabID
                    Button { withAnimation(.ikago) { state.select(tab.id) }; onSelection?() } label: {
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
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(hoveredID == tab.id ? colors.hover.opacity(2) : colors.hover)
                            .animation(reduceMotion ? nil : .easeOut(duration: hoveredID == tab.id ? 0.1 : 0.2), value: hoveredID == tab.id)
                        TabSelectionHighlight(shape: RoundedRectangle(cornerRadius: 12, style: .continuous), active: active,
                                              color: colors.selected, selection: selection, id: "pinned-active")
                    }
                    .onHover { inside in
                        guard !scrolling else { return }
                        if inside { hoveredID = tab.id }
                        else if hoveredID == tab.id { hoveredID = nil }
                    }
                    .onChange(of: scrolling) { _, now in if now, hoveredID == tab.id { hoveredID = nil } }
                    .help("Pinned tab: \(tab.displayTitle)\nReturns to this live tab. New addresses open separately.")
                    .contextMenu { TabContextMenu(tab: tab, state: state, commands: commands) }
                    .onMiddleClick { withAnimation(.ikago) { commands?.closeTab(tab.id) } }
                    .onDrag {
                        chrome.beginTabDrag(tab.id)
                        return TabDrag.provider(tab.id)
                    }
                    .tabDropTarget(tab, axis: .horizontal, state: state, chrome: chrome)
                }
            }
        .animation(reduceMotion ? nil : .ikagoQuick, value: state.pinnedTabs.map(\.id))
        .onDisappear { hoveredID = nil }
    }
}

/// Shared right-click menu for tab rows and pinned tiles.
struct TabContextMenu: View {
    let tab: TabItem
    let state: BrowserState
    weak var commands: BrowserCommands?

    var body: some View {
        Button(tab.pinned ? "Unpin — Keep as Regular Tab" : "Pin Tab — Keep This Tab") { state.togglePin(tab.id) }
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
        if !tab.pinned {
            Menu("Move to Group") {
                ForEach(state.spaceFolders.filter { $0.id != tab.folderID }) { folder in
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
                    Button(space.name) { state.moveTab(tab.id, toSpace: space.id) }
                }
            }
        }
        Divider()
        Button(tab.pinned ? "Unload Pinned Tab — Keep Pin" : "Close Tab") { commands?.closeTab(tab.id) }
    }
}
