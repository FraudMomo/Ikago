import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A dragged tab. Its own type (not text), so web pages ignore it and split-view targets
/// and the sidebar can take it.
struct TabDrag: Codable, Transferable {
    let id: String
    /// The other selected tabs travelling with the dragged one (`TabClick`), set when the drag starts.
    @MainActor static var companions: [String] = []
    static var transferRepresentation: some TransferRepresentation { CodableRepresentation(contentType: .ikagoTab) }

    /// Read the actual payload; drag UI state may end before asynchronous delivery finishes. A tab from another window
    /// is brought into `state`'s window first (`BrowserWindows.bring`), so the drop then places it like its own tabs.
    /// `reversed`: placed one by one after the same row, the last tab goes in first so they keep their order.
    static func load(_ provider: NSItemProvider, into state: BrowserState?, reversed: Bool = false,
                     perform: @escaping @MainActor (String) -> Void) {
        provider.loadDataRepresentation(forTypeIdentifier: UTType.ikagoTab.identifier) { data, _ in
            guard let data, let tab = try? JSONDecoder().decode(TabDrag.self, from: data) else { return }
            Task { @MainActor in
                let ids = travelling(with: tab.id)
                for id in reversed ? ids.reversed() : ids {
                    if let state { BrowserWindows.bring(id, into: state) }
                    perform(id)
                }
            }
        }
    }

    /// The dragged tab and the selected tabs travelling with it, in their sidebar order; the drop takes them all.
    @MainActor static func travelling(with id: String) -> [String] {
        let order = BrowserWindows.owner(of: id)?.state.navigationOrder.map(\.id) ?? []
        let others = companions.filter { $0 != id }
            .sorted { (order.firstIndex(of: $0) ?? .max) < (order.firstIndex(of: $1) ?? .max) }
        companions = []
        return [id] + others
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
    /// Heights for "Keep pinned tabs and groups in view": the pinned/groups part and the whole list.
    @State private var topHeight: CGFloat = 0
    /// Room for the scroll bar beside the rows, taken from the sidebar's 10 pt edge padding.
    static let scrollGutter: CGFloat = 8
    @State private var totalHeight: CGFloat = 0

    var body: some View {
        // One pass over the Space's tabs groups them by folder; the old per-folder filters walked every tab again
        // for each folder (and each header did it three more times).
        let groups = SidebarGroups(state.spaceTabs)
        let folders = state.spaceFolders
        let activeID = state.activeTabID
        var seen = Set(state.presentsSidebarPinGrid ? state.sidebarGridPinnedTabs.map(\.id) : [])
        let rowPins = groups.pinned.filter { !state.presentsSidebarPinGrid || $0.pinAsRow || state.splitGroup(of: $0.id) != nil }
        let folderIDs = Set(folders.map(\.id))
        let anchors = Dictionary(grouping: rowPins) { tab in tab.pinAfterFolderID.flatMap { folderIDs.contains($0) ? $0 : nil } ?? "" }
        let pinnedItems = state.listItems(anchors[""] ?? [], seen: &seen)
        let folderItems = GroupEntry.tree(state: state, groups: groups, anchors: anchors, activeID: activeID, seen: &seen)
        // With tabs above the page, ungrouped tabs live there; the sidebar keeps pins and groups.
        let looseItems = state.showsSidebarTopTabs ? [] : state.listItems(groups.loose, seen: &seen)
        let visibleItems = pinnedItems + folderItems.flatMap(\.visibleItems) + looseItems
        let activeIsListed = visibleItems.contains { $0.containsTab(activeID) }
        let order = pinnedItems.map(\.id) + folderItems.flatMap(\.order) + looseItems.map(\.id)
        // Optionally pinned rows and groups (everything above the New Tab line) stay put and only the tabs under them
        // scroll. While that part would take more than 60% of the height it scrolls with the rest, so it never pushes
        // the tabs out of reach.
        let wantsFixed = state.browserPreferences.pinnedRowsStayInView == true && !(pinnedItems.isEmpty && folderItems.isEmpty)
        let fixedTop = wantsFixed && (totalHeight == 0 || topHeight <= totalHeight * 0.6)
        let top = VStack(spacing: 2) {
            AnimatedListItems(items: pinnedItems) { item in itemView(item) }
            // Pinned rows and groups are different kinds: a short hairline between them, no heading.
            if !pinnedItems.isEmpty && !folderItems.isEmpty {
                Rectangle().fill(colors.separator).frame(height: 1)
                    .padding(.horizontal, 12).padding(.vertical, 3)
                    .transition(.opacity)
            }
            SidebarPinBoundary(state: state, chrome: chrome, afterFolderID: nil)
            ForEach(folderItems) { entry in branch(entry, showSelection: !activeIsListed) }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { topHeight = $0 }
        return VStack(spacing: 2) {
            if fixedTop {
                top
                    .animation(reduceMotion ? nil : .ikagoQuick, value: order)
                    .animation(reduceMotion ? nil : .ikagoQuick, value: folders.map { $0.id + ($0.parentID ?? "") })
            }
        GeometryReader { geometry in
            SidebarScrollView(chrome: chrome) {
                VStack(spacing: 2) {
                    if !fixedTop { top }
                    if state.chromeLayout.sidebarShowsNewTab && !state.showsSidebarTopTabs {
                        Rectangle().fill(colors.separator).frame(height: 1).padding(.horizontal, 10).padding(.vertical, 6)
                        NewTabRow(colors: colors) { commands?.newTab() }
                    }
                    AnimatedListItems(items: looseItems) { item in itemView(item) }
                    Color.clear.frame(minHeight: 40)
                        .tabListEndDrop(state: state, chrome: chrome)
                }
                .frame(minHeight: geometry.size.height, alignment: .top)
                // The scroll view reaches into the sidebar's edge padding; the rows stop where they always did, so the
                // scroll bar has its own gutter and never draws over them.
                .padding(.trailing, Self.scrollGutter)
                // Structure changes reflow in 0.12 s. Selection is not animated here: the highlight animates itself,
                // and animating the whole list on every selection slid rows and the content height while scrolling.
                .animation(reduceMotion ? nil : .ikagoQuick, value: order)
                // Groups being added, removed or reordered; opening one animates from its own section.
                .animation(reduceMotion ? nil : .ikagoQuick, value: folders.map { $0.id + ($0.parentID ?? "") })
                .animation(reduceMotion ? nil : .ikagoQuick, value: state.splits)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.trailing, -Self.scrollGutter)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { totalHeight = $0 }
        .animation(reduceMotion ? nil : .ikagoQuick, value: fixedTop)
        .recordLayout("sidebar-tab-list")
    }

    /// A group whose tabs are all closed or asleep (and none of them is on screen).
    static func isSleeping(_ tabs: [TabItem], activeID: String?) -> Bool {
        !tabs.isEmpty && tabs.allSatisfy { $0.isUnloaded && $0.id != activeID }
    }

    /// A group with the groups inside it, then its tabs. One stack per group, so its empty pin list and drop line add
    /// no list spacing: groups sit closer together than rows, like bookmarks in a book. Recursive, hence `AnyView`.
    private func branch(_ entry: GroupEntry, showSelection: Bool) -> AnyView {
        AnyView(VStack(spacing: 0) {
            SidebarFolderSection(folder: entry.folder, state: state, chrome: chrome,
                                 colors: colors, selection: selection, showSelection: showSelection,
                                 count: entry.count, containsActiveTab: entry.containsActive,
                                 sleeping: entry.sleeping, depth: entry.depth, commands: commands) {
                ForEach(entry.children) { child in branch(child, showSelection: showSelection) }
                AnimatedListItems(items: entry.items) { item in itemView(item) }
            }
            VStack(spacing: 2) { AnimatedListItems(items: entry.pins) { item in itemView(item) } }
                .padding(.top, entry.pins.isEmpty ? 0 : 2)
            SidebarPinBoundary(state: state, chrome: chrome, afterFolderID: entry.folder.id)
        })
    }

    @ViewBuilder private func itemView(_ item: TabListItem) -> some View {
        switch item {
        case .tab(let tab): row(tab)
        case .group(let tabs):
            SplitGroupRow(tabs: tabs, state: state, chrome: chrome, colors: colors, selection: selection, commands: commands)
                .transition(.scale(scale: 0.95).combined(with: .opacity))
        }
    }

    private func row(_ tab: TabItem) -> some View {
        TabRowView(tab: tab, isActive: tab.id == state.activeTabID, isInSplit: false,
                   colors: colors, selection: selection, commands: commands)
            .tabSelectionTint(chrome.selectedTabIDs.contains(tab.id), colors: colors)
            .onTapGesture {
                TabClick.handle(tab, state: state, chrome: chrome, commands: commands) {
                    withAnimation(reduceMotion ? nil : .ikago) { state.select(tab.id) }
                    onSelection?()
                }
            }
            .contextMenu { TabContextMenu(tab: tab, state: state, commands: commands) }
            .onMiddleClick { withAnimation(reduceMotion ? nil : .ikago) { commands?.closeTab(tab.id) } }
            .onDrag {
                chrome.beginTabDrag(tab.id)
                return TabDrag.provider(tab.id)
            } preview: {
                TabDragPreview(tab: tab, colors: colors, count: chrome.selectedTabIDs.contains(tab.id) ? chrome.selectedTabIDs.count : 1)
            }
            .travellingWithDrag(chrome.draggingTabID != nil && chrome.draggingTabID != tab.id && chrome.selectedTabIDs.contains(tab.id)
                                && chrome.selectedTabIDs.contains(chrome.draggingTabID ?? ""))
            .tabDropTarget(tab, axis: .vertical, state: state, chrome: chrome)
            .recordLayout("sidebar-tab-\(tab.id)")
            .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity),
                                    removal: .opacity.combined(with: .scale(scale: 0.96))))
    }
}

/// Keeps removed row models alive inside the isolated list host long enough to animate their slots closed.
/// Closing a tab still releases its page immediately; these snapshots contain only lightweight tab metadata.
private struct AnimatedListItems<Content: View>: View {
    struct Retired: Identifiable {
        let id: String
        let item: TabListItem
        let index: Int
    }
    struct Entry: Identifiable {
        let id: String
        let item: TabListItem
        let retiring: Bool
    }

    let items: [TabListItem]
    @ViewBuilder let content: (TabListItem) -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rendered: [TabListItem] = []
    @State private var retired: [Retired] = []

    init(items: [TabListItem], @ViewBuilder content: @escaping (TabListItem) -> Content) {
        self.items = items
        self.content = content
        _rendered = State(initialValue: items)
    }

    private var entries: [Entry] {
        // Live rows come directly from the model. Only departing metadata is cached.
        var result = rendered.map { Entry(id: $0.id, item: $0, retiring: false) }
        for item in retired.filter({ old in !items.contains { $0.id == old.id } }).sorted(by: { $0.index < $1.index }) {
            result.insert(Entry(id: item.id, item: item.item, retiring: true), at: min(item.index, result.count))
        }
        return result
    }

    var body: some View {
        VStack(spacing: 2) {
            ForEach(entries) { entry in
                content(entry.item)
                    .frame(height: entry.retiring ? 0 : nil)
                    .opacity(entry.retiring ? 0 : 1)
                    .clipped()
                    .allowsHitTesting(!entry.retiring)
                    .accessibilityHidden(entry.retiring)
                    .animation(reduceMotion ? nil : .ikagoQuick, value: entry.retiring)
            }
        }
        .onChange(of: items.map(\.id)) { _, ids in
            let live = Set(ids)
            let leaving = rendered.enumerated().compactMap { index, item in
                live.contains(item.id) ? nil : Retired(id: item.id, item: item, index: index)
            }
            guard !leaving.isEmpty || rendered.map(\.id) != ids else { return }
            withAnimation(reduceMotion ? nil : .ikagoQuick) {
                rendered = items
                retired.removeAll { live.contains($0.id) }
                retired.append(contentsOf: leaving)
            }
            guard !leaving.isEmpty else { return }
            let retiredIDs = Set(leaving.map(\.id))
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(180))
                withAnimation(reduceMotion ? nil : .ikagoQuick) {
                    retired.removeAll { retiredIDs.contains($0.id) }
                }
            }
        }
    }
}

/// What follows the pointer while dragging tabs: the tab, and with several selected, a stack of cards behind it and a
/// badge with how many are moving.
struct TabDragPreview: View {
    let tab: TabItem
    let colors: Palette
    var count = 1

    var body: some View {
        let card = colors.isDark ? Color(white: 0.2) : .white
        let shape = RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
        HStack(spacing: 8) {
            FaviconView(tab: tab)
            Text(tab.displayTitle).lineLimit(1).font(.system(size: 13, weight: .medium))
        }
        .padding(.horizontal, 12).frame(width: 190, height: 32, alignment: .leading)
        // Plain fills: drag previews are rendered offscreen, where Liquid Glass can't draw.
        .background(shape.fill(card).overlay(shape.strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)))
        .background {
            ForEach(Array((1..<min(count, 3)).reversed()), id: \.self) { depth in
                shape.fill(card.opacity(0.85)).overlay(shape.strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5))
                    .offset(x: CGFloat(depth) * 4, y: CGFloat(depth) * 4)
            }
        }
        .overlay(alignment: .topTrailing) {
            if count > 1 {
                Text("\(count)").font(.system(size: 11, weight: .bold).monospacedDigit()).foregroundStyle(.white)
                    .padding(.horizontal, 6).frame(minWidth: 20, minHeight: 20)
                    .background(Capsule().fill(colors.accent))
                    .offset(x: 8, y: -8)
            }
        }
        .padding(10)
        .opacity(0.9)
    }
}

extension View {
    /// A selected tab travelling with the one being dragged: it fades and tucks in, as if stacked under the pointer.
    func travellingWithDrag(_ travelling: Bool) -> some View {
        opacity(travelling ? 0.35 : 1)
            .scaleEffect(travelling ? 0.96 : 1)
            .animation(.ikago, value: travelling)
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
            .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(hovering ? colors.hover : .clear))
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
