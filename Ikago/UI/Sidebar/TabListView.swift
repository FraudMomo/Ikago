import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A dragged tab. Its own type (not text), so web pages ignore it and split-view targets
/// and the sidebar can take it.
struct TabDrag: Codable, Transferable {
    let id: String
    static var transferRepresentation: some TransferRepresentation { CodableRepresentation(contentType: .ikagoTab) }

    /// Read the actual payload; drag UI state may end before asynchronous delivery finishes.
    static func load(_ provider: NSItemProvider, perform: @escaping @MainActor (String) -> Void) {
        provider.loadDataRepresentation(forTypeIdentifier: UTType.ikagoTab.identifier) { data, _ in
            guard let data, let tab = try? JSONDecoder().decode(TabDrag.self, from: data) else { return }
            Task { @MainActor in perform(tab.id) }
        }
    }

    /// Item provider carrying only this type (no text or file fallbacks a web view would grab).
    static func provider(_ id: String) -> NSItemProvider {
        let provider = NSItemProvider()
        let data = (try? JSONEncoder().encode(TabDrag(id: id))) ?? Data()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.ikagoTab.identifier, visibility: .ownProcess) { done in
            done(data, nil)
            return nil
        }
        return provider
    }
}

extension UTType {
    static let ikagoTab = UTType(exportedAs: "app.ikago.tab")
}

/// New Tab, the active Space's folders and loose tabs, with drag-and-drop reordering.
struct TabListView: View {
    let state: BrowserState
    let chrome: ChromeModel
    let colors: Palette
    weak var commands: BrowserCommands?
    var onSelection: (() -> Void)? = nil
    @Namespace private var selection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // One pass over the Space's tabs groups them by folder; the old per-folder filters walked every tab again
        // for each folder (and each header did it three more times).
        let groups = SidebarGroups(state.spaceTabs)
        let folders = state.spaceFolders
        let activeID = state.activeTabID
        let activeFolderID = state.activeTab?.folderID
        var seen = Set(state.presentsSidebarPinGrid ? groups.pinned.filter { state.splitGroup(of: $0.id) == nil }.map(\.id) : [])
        let pinnedItems = state.presentsSidebarPinGrid ? [] : state.listItems(groups.pinned, seen: &seen)
        let folderItems = folders.map { (folder: $0, count: groups.tabs(in: $0.id).count, items: state.listItems(groups.tabs(in: $0.id), seen: &seen)) }
        let looseItems = state.listItems(groups.loose, seen: &seen)
        let visibleItems = pinnedItems + folderItems.filter { $0.folder.isOpen }.flatMap(\.items) + looseItems
        let activeIsListed = visibleItems.contains { $0.containsTab(activeID) }
        let order = groups.pinned.map(\.id) + folders.flatMap { groups.tabs(in: $0.id).map(\.id) } + groups.loose.map(\.id)
        return GeometryReader { geometry in
            SidebarScrollView(chrome: chrome) {
                VStack(spacing: 2) {
                    ForEach(pinnedItems) { item in itemView(item) }
                    ForEach(folderItems, id: \.folder.id) { entry in
                        SidebarFolderSection(folder: entry.folder, state: state, chrome: chrome,
                                             colors: colors, selection: selection, showSelection: !activeIsListed,
                                             count: entry.count, containsActiveTab: activeFolderID == entry.folder.id, commands: commands) {
                            ForEach(entry.items) { item in
                                itemView(item)
                            }
                        }
                    }
                    if state.chromeLayout.sidebarShowsNewTab {
                        // Horizontal line
                        Divider().padding(.vertical, 6).containerRelativeFrame(.horizontal) { size, axis in
                            size * 0.9
                        }
                        NewTabRow(colors: colors) { commands?.newTab() }
                    }
                    ForEach(looseItems) { item in itemView(item) }
                    Color.clear.frame(minHeight: 40)
                        .tabListEndDrop(state: state, chrome: chrome)
                }
                .frame(minHeight: geometry.size.height, alignment: .top)
                // Structure changes reflow in 0.12 s. Selection is not animated here: the highlight animates itself,
                // and animating the whole list on every selection slid rows and the content height while scrolling.
                .animation(reduceMotion ? nil : .ikagoQuick, value: order)
                // Groups being added, removed or reordered; opening one animates from its own section.
                .animation(reduceMotion ? nil : .ikagoQuick, value: folders.map(\.id))
                .animation(reduceMotion ? nil : .ikagoQuick, value: state.splits)
            }
            .frame(maxHeight: .infinity)
        }
    }

    @ViewBuilder private func itemView(_ item: TabListItem) -> some View {
        switch item {
        case .tab(let tab): row(tab)
        case .group(let tabs):
            SplitGroupRow(tabs: tabs, state: state, chrome: chrome, colors: colors, selection: selection, commands: commands)
                .transition(.scale(scale: 0.95).combined(with: .opacity))
        case .folder: EmptyView()  // the sidebar draws folders itself
        }
    }

    private func row(_ tab: TabItem) -> some View {
        TabRowView(tab: tab, isActive: tab.id == state.activeTabID, isInSplit: false,
                   colors: colors, selection: selection, commands: commands)
            .onTapGesture { withAnimation(reduceMotion ? nil : .ikago) { state.select(tab.id) }; onSelection?() }
            .contextMenu { TabContextMenu(tab: tab, state: state, commands: commands) }
            .onMiddleClick { withAnimation(reduceMotion ? nil : .ikago) { commands?.closeTab(tab.id) } }
            .onDrag {
                chrome.beginTabDrag(tab.id)
                return TabDrag.provider(tab.id)
            } preview: {
                TabDragPreview(tab: tab, colors: colors)
            }
            .tabDropTarget(tab, axis: .vertical, state: state, chrome: chrome)
            .recordLayout("sidebar-tab-\(tab.id)")
            .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity),
                                    removal: .opacity.combined(with: .scale(scale: 0.96))))
    }
}

struct TabDragPreview: View {
    let tab: TabItem
    let colors: Palette

    var body: some View {
        HStack(spacing: 8) {
            FaviconView(tab: tab)
            Text(tab.displayTitle).lineLimit(1).font(.system(size: 13, weight: .medium))
        }
        .padding(.horizontal, 12).frame(maxWidth: 180).frame(height: 30)
        // Plain fill: drag previews are rendered offscreen, where Liquid Glass can't draw.
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(colors.isDark ? Color(white: 0.2) : .white))
        .opacity(0.75)
    }
}

private struct NewTabRow: View {
    let colors: Palette
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 12, weight: .semibold)).frame(width: 16)
                Text("New Tab")
                Spacer()
            }
            .font(.system(size: 13))
            .foregroundStyle(colors.secondary)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hovering ? colors.hover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sidebarHover($hovering)
        .animation(.ikagoQuick, value: hovering)
        .help("New Tab (⌘T)")
    }
}


/// A Space's tabs grouped in one pass: pinned, by folder, and loose, each in tab order.
@MainActor
struct SidebarGroups {
    private(set) var pinned: [TabItem] = []
    private(set) var loose: [TabItem] = []
    private var byFolder: [String: [TabItem]] = [:]

    init(_ tabs: [TabItem]) {
        for tab in tabs {
            if tab.pinned { pinned.append(tab) }
            else if let folder = tab.folderID { byFolder[folder, default: []].append(tab) }
            else { loose.append(tab) }
        }
    }

    func tabs(in folderID: String) -> [TabItem] { byFolder[folderID] ?? [] }
}
