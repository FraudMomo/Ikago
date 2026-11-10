import AppKit
import SwiftUI

/// Presentation sections retain each member's scroll identity while drawing one group surface.
enum IslandStripSection: Identifiable {
    case item(TabListItem)
    case folder(TabFolder, [TabListItem], Int)

    var id: String {
        switch self {
        case .item(let item): item.id
        case .folder(let folder, _, _): "folder:" + folder.id
        }
    }

    /// The layout still budgets every tab individually, including members of expanded groups.
    var items: [TabListItem] {
        switch self {
        case .item(let item): [item]
        case .folder(let folder, let members, let count): [.folder(folder, count)] + members
        }
    }

    var hasMembers: Bool {
        if case .folder(_, let members, _) = self { return !members.isEmpty }
        return false
    }
}

/// Expanded groups sit in a faint capsule, with regular tab selection and hover surfaces inside.
struct IslandFolderGroup<Content: View>: View {
    let folder: TabFolder
    let count: Int
    let hasMembers: Bool
    let height: CGFloat
    let colors: Palette
    let state: BrowserState
    let chrome: ChromeModel
    let selection: Namespace.ID
    let representsActiveTab: Bool
    weak var commands: BrowserCommands?
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: TabStripLayout.spacing) {
            FolderChip(folder: folder, count: count, height: height, colors: colors, state: state,
                       chrome: chrome, selection: selection, isSelected: representsActiveTab, commands: commands)
            content()
        }
        .padding(.horizontal, hasMembers ? TabStripLayout.groupInset : 0)
        .frame(height: height)
        .background {
            if hasMembers {
                Capsule().fill(colors.hover.opacity(0.55))
                Capsule().strokeBorder(colors.separator, lineWidth: 0.5)
            }
        }
    }
}

/// A neutral group control; its color marker and disclosure never change position on hover.
struct FolderChip: View {
    let folder: TabFolder
    let count: Int
    let height: CGFloat
    let colors: Palette
    let state: BrowserState
    let chrome: ChromeModel
    let selection: Namespace.ID
    let isSelected: Bool
    weak var commands: BrowserCommands?
    @State private var hovering = false
    @State private var targeted = false

    @MainActor static func width(of folder: TabFolder, count: Int, style: GroupLabelStyle, showsCount: Bool) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        let title = (folder.name as NSString).size(withAttributes: [.font: font]).width
        let counter = folder.isOpen || !showsCount ? 0 : (String(count) as NSString).size(withAttributes: [.font: font]).width + 7
        let labelInsets: CGFloat = style == .colorPill ? 16 : 14
        return min(154, max(72, ceil(title + counter + labelInsets + 33)))
    }

    var body: some View {
        Button { withAnimation(.ikago) { state.toggleFolder(folder.id) } } label: {
            HStack(spacing: 7) {
                FolderLabel(folder: folder, colors: colors, size: 11.5, isActive: isSelected, style: state.groupLabelStyle)
                if !folder.isOpen && state.showsGroupTabCounts {
                    Text(count, format: .number)
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(colors.tertiary)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 7, weight: .semibold))
                    .rotationEffect(.degrees(folder.isOpen ? 90 : 0))
                    .foregroundStyle(hovering ? colors.secondary : colors.tertiary)
                    .frame(width: 8)
            }
            .padding(.horizontal, 9)
            .frame(width: Self.width(of: folder, count: count, style: state.groupLabelStyle,
                                    showsCount: state.showsGroupTabCounts), height: height)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .background(ActiveTabScrollAnchor(active: isSelected))
        .recordLayout("folder-\(folder.id)")
        .background {
            TabSelectionHighlight(shape: Capsule(), active: isSelected,
                                  color: colors.selected.opacity(colors.isDark ? 1 : 0.9),
                                  selection: selection, id: "island-active")
            if targeted || (hovering && !isSelected) {
                Capsule().fill(targeted ? colors.selected : colors.hover)
            }
        }
        .onHover { hovering = $0 }
        .animation(.ikagoQuick, value: hovering)
        .animation(.ikagoQuick, value: targeted)
        .dropDestination(for: TabDrag.self) { drags, _ in
            chrome.endTabDrag()
            guard let id = drags.first?.id, state.tab(id) != nil else { return false }
            withAnimation(.ikago) { state.moveToFolder(id, folderID: folder.id) }
            return true
        } isTargeted: { targeted = $0 }
        .contextMenu { FolderContextMenu(folder: folder, state: state, commands: commands) }
        .accessibilityLabel(folder.name)
        .accessibilityValue(folder.disclosureValue(count: count, showsCount: state.showsGroupTabCounts))
        .help(folder.disclosureHelp(count: count, showsCount: state.showsGroupTabCounts))
    }
}
