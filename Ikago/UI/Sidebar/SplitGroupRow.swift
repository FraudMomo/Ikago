import SwiftUI

/// A tab, or a split group shown as one item, in sidebar/top-bar order.
enum TabListItem: Identifiable {
    case tab(TabItem)
    case group([TabItem])
    /// Top bar only: a folder's chip (and how many tabs it holds), placed before its tabs.
    case folder(TabFolder, Int)

    var id: String {
        switch self {
        case .tab(let tab): tab.id
        case .group(let tabs): "split:" + tabs.map(\.id).joined(separator: ",")
        case .folder(let folder, _): "folder:" + folder.id
        }
    }

    func containsTab(_ id: String?) -> Bool {
        switch self {
        case .tab(let tab): tab.id == id
        case .group(let tabs): tabs.contains { $0.id == id }
        case .folder: false
        }
    }
}

extension BrowserState {
    /// Groups split tabs into one item, placed where the group's first listed tab is.
    /// `seen` is shared across lists so a group appears once.
    func listItems(_ list: [TabItem], seen: inout Set<String>) -> [TabListItem] {
        var items: [TabListItem] = []
        for tab in list where !seen.contains(tab.id) {
            if let group = splitGroup(of: tab.id) {
                let members = group.compactMap { self.tab($0) }
                members.forEach { seen.insert($0.id) }
                items.append(.group(members))
            } else {
                seen.insert(tab.id)
                items.append(.tab(tab))
            }
        }
        return items
    }
}

/// A split group in the sidebar: one rounded row holding a chip per tab. Click a chip to
/// focus it; hover for "Separate"; right-click for more.
struct SplitGroupRow: View {
    let tabs: [TabItem]
    let state: BrowserState
    let chrome: ChromeModel
    let colors: Palette
    let selection: Namespace.ID
    weak var commands: BrowserCommands?
    @State private var hovering = false

    var body: some View {
        let shown = tabs.contains { $0.id == state.activeTabID }
        HStack(spacing: 2) {
            ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                if index > 0 { Rectangle().fill(colors.separator).frame(width: 1, height: 16) }
                SplitChip(tab: tab, focused: tab.id == state.activeTabID && tabs.count > 1, colors: colors, compact: tabs.count > 2, commands: commands)
                    .onTapGesture { withAnimation(.ikago) { state.select(tab.id) } }
                    .contextMenu { TabContextMenu(tab: tab, state: state, commands: commands) }
                    .onMiddleClick { withAnimation(.ikago) { commands?.closeTab(tab.id) } }
                    .onDrag {
                        chrome.beginTabDrag(tab.id)
                        return TabDrag.provider(tab.id)
                    }
            }
            if hovering {
                Button { withAnimation(.ikago) { state.unsplitGroup(containing: tabs[0].id) } } label: {
                    Image(systemName: "rectangle.split.2x1").font(.system(size: 10, weight: .semibold))
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(colors.hover.opacity(1.5)))
                }
                .buttonStyle(.plain)
                .foregroundStyle(colors.secondary)
                .help("Separate Tabs")
                .transition(.opacity.combined(with: .scale(scale: 0.7)))
            }
        }
        .padding(.horizontal, 4)
        .frame(height: 34)
        .background {
            TabSelectionHighlight(shape: RoundedRectangle(cornerRadius: 10, style: .continuous), active: shown,
                                  color: colors.selected, selection: selection, id: "active-tab")
            if !shown {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hovering ? colors.hover.opacity(1.6) : colors.hover)
            }
        }
        .contentShape(Rectangle())
        .tabDropTarget(tabs[0], axis: .vertical, state: state, chrome: chrome)
        .sidebarHover($hovering)
        .animation(.ikagoQuick, value: hovering)
        .contextMenu {
            Button("Separate Tabs") { withAnimation(.ikago) { state.unsplitGroup(containing: tabs[0].id) } }
            Button("Rotate Split") { withAnimation(.ikago) { state.toggleSplitOrientation() } }
        }
    }
}

/// One tab inside a split group (sidebar row or top-bar capsule).
struct SplitChip: View {
    let tab: TabItem
    let focused: Bool
    let colors: Palette
    var compact = false
    weak var commands: BrowserCommands?

    var body: some View {
        HStack(spacing: 6) {
            FaviconView(tab: tab, size: 14)
            if !compact || focused {
                Text(tab.displayTitle).lineLimit(1).font(.system(size: 12, weight: focused ? .semibold : .regular))
                    .foregroundStyle(focused ? colors.text : colors.secondary)
            }
            if focused && tab.isLoading { PageLoadButton(tab: tab, colors: colors, commands: commands) }
        }
        .padding(.horizontal, 7)
        .frame(maxWidth: compact && !focused ? 30 : .infinity, minHeight: 26)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(focused ? colors.hover.opacity(1.6) : .clear))
        .overlay(alignment: .bottom) { PageLoadProgress(tab: tab, colors: colors).padding(.horizontal, 7) }
        .contentShape(Rectangle())
        .help(tab.displayTitle)
    }
}
