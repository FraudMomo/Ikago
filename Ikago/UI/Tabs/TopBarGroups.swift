import SwiftUI

/// Tab groups in the Sidebar + Tabs row, like Chrome's: a chip in the group's color leads its tabs, a click collapses or
/// expands them (the same open state as the sidebar's), and a line in the color runs under the group's tabs. Hidden
/// groups leave the row and come back from `HiddenGroupsButton`. Where groups show is `GroupPlacement`.
enum TopRowEntry: Identifiable {
    case chip(TabFolder, count: Int)
    case item(TabListItem, group: TabFolder?)

    var id: String {
        switch self {
        case .chip(let folder, _): "chip:" + folder.id
        case .item(let item, _): item.id
        }
    }

    var item: TabListItem? { if case .item(let item, _) = self { item } else { nil } }
    var group: TabFolder? {
        switch self {
        case .chip(let folder, _): folder
        case .item(_, let group): group
        }
    }

    /// The row in order: each shown top-level group's chip, then its tabs (all of them while open; only the active
    /// tab while collapsed, so the page on screen always has its tab), then the ungrouped tabs.
    @MainActor static func row(state: BrowserState, seen: inout Set<String>) -> [TopRowEntry] {
        var entries: [TopRowEntry] = []
        if state.showsGroupsInTopBar {
            for folder in state.childFolders(of: nil) where folder.isClosed != true {
                let members = state.tabs(inSubtree: folder)
                entries.append(.chip(folder, count: members.count))
                let shown = folder.isOpen ? members : members.filter { $0.id == state.activeTabID }
                entries += state.listItems(shown, seen: &seen).map { .item($0, group: folder) }
            }
        }
        entries += state.listItems(state.looseTabs, seen: &seen).map { .item($0, group: nil) }
        return entries
    }
}

extension TabFolder {
    /// The group's color for chips and underlines; nil for a group without one.
    var chipColor: Color? { tagValue?.color }

    /// A chip's width: its name (or icon alone) and, while collapsed, its tab count.
    func chipWidth(showsCount: Bool) -> CGFloat {
        let text = name.isEmpty ? 0 : min(118, CGFloat(name.count) * 6.8 + 4)
        let icon: CGFloat = icon == nil && !name.isEmpty ? 0 : 16
        let count: CGFloat = showsCount && !isOpen ? 20 : 0
        return 20 + text + icon + count + (text > 0 && icon > 0 ? 4 : 0) + 8
    }
}

/// A group's chip: click to collapse or expand, right-click for the group's menu, drag to move the group (before, into
/// or after another chip, or onto a Space), and drop tabs on it to add them.
struct TopBarGroupChip: View {
    let folder: TabFolder
    let count: Int
    let state: BrowserState
    let chrome: ChromeModel
    let colors: Palette
    weak var commands: BrowserCommands?
    @State private var hovering = false
    @State private var tabTargeted = false
    @State private var zone: GroupDropZone?
    @State private var width = MeasuredLength()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tint: Color { folder.chipColor ?? colors.text.opacity(0.14) }
    /// Text on the chip: dark on the light colors, white on the rest, the window's text on a plain chip.
    private var ink: Color {
        guard let tag = folder.tagValue else { return colors.text }
        return [.yellow, .orange].contains(tag) ? .black.opacity(0.82) : .white
    }

    var body: some View {
        let showsCount = state.showsGroupTabCounts && !folder.isOpen
        Button { withAnimation(reduceMotion ? nil : .ikagoQuick) { state.toggleFolder(folder.id) } } label: {
            HStack(spacing: 4) {
                if folder.icon != nil || folder.name.isEmpty {
                    FolderIcon(folder: folder, colors: colors, size: 10.5)
                        .foregroundStyle(ink)
                        .frame(width: 14)
                }
                if !folder.name.isEmpty {
                    Text(folder.name).font(.system(size: 11.5, weight: .semibold)).fadeTruncated(fade: 12)
                }
                if showsCount {
                    Text(count, format: .number).font(.system(size: 10, weight: .bold).monospacedDigit())
                        .opacity(0.75)
                }
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(tint.opacity(folder.chipColor == nil ? 1 : (hovering ? 1 : 0.88)))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(colors.accent, lineWidth: 2)
                    .opacity(tabTargeted || zone == .into ? 1 : 0)
            }
            .scaleEffect(tabTargeted || zone == .into ? 1.06 : 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .opacity(chrome.draggingFolderID == folder.id ? 0.45 : 1)
        .overlay(alignment: zone == .after ? .trailing : .leading) {
            if zone == .before || zone == .after { GroupInsertionLine(colors: colors, vertical: true) }
        }
        .animation(.ikagoQuick, value: zone)
        .animation(.ikagoQuick, value: tabTargeted)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width.value = $0 }
        .onDrag {
            chrome.beginFolderDrag(folder.id)
            return GroupDrag.provider(folder.id)
        } preview: {
            GroupDragPreview(folder: folder, colors: colors)
        }
        .onDrop(of: [.ikagoTab, .ikagoGroup], delegate: FolderHeaderDropDelegate(
            folder: folder, state: state, chrome: chrome, length: width,
            tabTargeted: $tabTargeted, zone: $zone, horizontal: true))
        .onChange(of: chrome.draggingFolderID) { _, id in if id == nil { zone = nil } }
        .contextMenu { FolderContextMenu(folder: folder, state: state, commands: commands) }
        .help("\(folder.name.isEmpty ? "Group" : folder.name) · \(count) \(count == 1 ? "tab" : "tabs") — click to \(folder.isOpen ? "collapse" : "expand")")
        .accessibilityLabel(folder.name.isEmpty ? "Tab group" : folder.name)
        .accessibilityValue(folder.isOpen ? "Expanded" : "Collapsed")
    }
}

/// A group's color in the row, like Chrome: a 2 pt line along the bottom of its tabs, and around the active tab an
/// outline in the same color that follows its arch (`AttachedTabOutline`) and meets the line at both flares, so the tab
/// you are on rises out of its group's line.
struct TopBarGroupLine: ViewModifier {
    let group: TabFolder?
    let active: Bool
    let colors: Palette

    static let width: CGFloat = 2

    func body(content: Content) -> some View {
        let color = group.map { $0.chipColor ?? colors.text.opacity(0.25) }
        content
            .overlay(alignment: .bottom) {
                if let color, !active {
                    Rectangle().fill(color).frame(height: Self.width).allowsHitTesting(false)
                }
            }
            .overlay {
                if let color, active {
                    // Inset by half the stroke, so its flares end on the same line as the neighbours' lines.
                    AttachedTabOutline()
                        .stroke(color, style: StrokeStyle(lineWidth: Self.width, lineCap: .butt, lineJoin: .round))
                        .padding(.vertical, Self.width / 2)
                        .allowsHitTesting(false)
                }
            }
    }
}

/// The active tab's arch (`AttachedTabShape`) without its bottom edge, for the group outline.
struct AttachedTabOutline: Shape {
    func path(in rect: CGRect) -> Path {
        var path = AttachedTabShape().path(in: rect)
        // The shape closes along its bottom; drawing it open leaves only the flares, sides and top.
        path = Path { open in
            var first = true
            path.forEach { element in
                switch element {
                case .move(let to): open.move(to: to); first = false
                case .line(let to): open.addLine(to: to)
                case .quadCurve(let to, let control): open.addQuadCurve(to: to, control: control)
                case .curve(let to, let c1, let c2): open.addCurve(to: to, control1: c1, control2: c2)
                case .closeSubpath: break
                }
            }
            _ = first
        }
        return path
    }
}

/// Lists the Space's hidden groups in the tab row; choosing one shows it again with its tabs.
struct HiddenGroupsButton: View {
    let state: BrowserState
    let colors: Palette

    static let width: CGFloat = 34

    var body: some View {
        let hidden = state.closedFolders
        Menu {
            Section("Hidden Groups") {
                ForEach(hidden) { folder in
                    let count = state.tabs(inSubtree: folder).count
                    Button("\(folder.name.isEmpty ? "Group" : folder.name) (\(count) \(count == 1 ? "tab" : "tabs"))") {
                        withAnimation(.ikagoQuick) { state.reopenFolder(folder.id) }
                    }
                }
            }
        } label: {
            HStack(spacing: 2) {
                Image(systemName: "square.stack.3d.down.right").font(.system(size: 12, weight: .medium))
                Text("\(hidden.count)").font(.system(size: 9.5, weight: .bold).monospacedDigit())
            }
            .foregroundStyle(colors.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .tint(colors.secondary)
        .fixedSize()
        .frame(width: Self.width, height: SidebarTopTabs.tabHeight)
        .help("Hidden groups: \(hidden.map(\.name).joined(separator: ", "))")
        .accessibilityLabel("Hidden groups")
    }
}
