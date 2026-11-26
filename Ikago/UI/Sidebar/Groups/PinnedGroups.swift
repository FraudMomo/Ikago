import SwiftUI

/// Groups pinned like tabs (`TabFolder.isPinned`): a button among the pins that opens a menu of the group's tabs, the
/// way a bookmarks folder does. Out of the list of groups; its tabs stay when closed, like pinned tabs. In the full
/// sidebar a row each under the essentials (`PinnedGroupRows`); in the icon rail a tile each with the pins
/// (`PinnedGroupTile`). Tabs dropped on one join the group.
struct PinnedGroupRows: View {
    let state: BrowserState
    let chrome: ChromeModel
    weak var commands: BrowserCommands?

    var body: some View {
        let folders = state.pinnedFolders
        if !folders.isEmpty {
            VStack(spacing: 2) {
                ForEach(folders) { folder in PinnedGroupRow(folder: folder, state: state, chrome: chrome, commands: commands) }
            }
            .transition(.opacity)
        }
    }
}

private struct PinnedGroupRow: View {
    let folder: TabFolder
    let state: BrowserState
    let chrome: ChromeModel
    weak var commands: BrowserCommands?
    @State private var hovering = false
    @State private var targeted = false

    var body: some View {
        let colors = state.palette
        let tabs = state.tabs(inSubtree: folder)
        let active = tabs.first { $0.id == state.activeTabID }
        Menu {
            PinnedGroupMenu(folder: folder, state: state, commands: commands)
        } label: {
            HStack(spacing: 9) {
                FolderIcon(folder: folder, colors: colors, size: 13).frame(width: 16)
                VStack(alignment: .leading, spacing: 0) {
                    Text(folder.name).font(.system(size: 13, weight: active == nil ? .regular : .medium))
                        .foregroundStyle(colors.text).lineLimit(1)
                    // The group's tab on screen, so the page always has its place in the sidebar.
                    if let active {
                        Text(active.displayTitle).font(.system(size: 11)).foregroundStyle(colors.secondary).lineLimit(1)
                    }
                }
                .fadeTruncated()
                Spacer(minLength: 4)
                Text("\(tabs.count)").font(.system(size: 11).monospacedDigit()).foregroundStyle(colors.tertiary)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(hovering ? colors.secondary : colors.tertiary)
            }
            .padding(.horizontal, 10).frame(height: active == nil ? 34 : 40)
            .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                .fill(active != nil ? colors.selected : hovering || targeted ? colors.hover : .clear))
            .overlay {
                if targeted {
                    RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                        .strokeBorder(folder.tagValue?.color ?? colors.accent, lineWidth: 1.5)
                }
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
        .sidebarHover($hovering)
        .pinnedGroupDrop(folder: folder, state: state, chrome: chrome, targeted: $targeted)
        .contextMenu { FolderContextMenu(folder: folder, state: state, commands: commands) }
        .animation(.ikagoQuick, value: hovering)
        .animation(.ikagoQuick, value: targeted)
        .help("\(folder.name) · \(tabs.count) \(tabs.count == 1 ? "tab" : "tabs")")
        .accessibilityLabel("\(folder.name), pinned group")
    }
}

/// A pinned group in the icon rail: its icon on a tile among the pins, the same menu on click.
struct PinnedGroupTile: View {
    let folder: TabFolder
    let state: BrowserState
    let chrome: ChromeModel
    weak var commands: BrowserCommands?
    @State private var hovering = false
    @State private var targeted = false

    var body: some View {
        let colors = state.palette
        let tabs = state.tabs(inSubtree: folder)
        let active = tabs.contains { $0.id == state.activeTabID }
        Menu {
            PinnedGroupMenu(folder: folder, state: state, commands: commands)
        } label: {
            FolderIcon(folder: folder, colors: colors, size: 16)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                    .fill(active ? colors.selected : hovering || targeted ? colors.hover : colors.text.opacity(0.06)))
                .overlay {
                    if targeted {
                        RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                            .strokeBorder(folder.tagValue?.color ?? colors.accent, lineWidth: 1.5)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
        .frame(width: 36, height: 36)
        .sidebarHover($hovering)
        .pinnedGroupDrop(folder: folder, state: state, chrome: chrome, targeted: $targeted)
        .contextMenu { FolderContextMenu(folder: folder, state: state, commands: commands) }
        .help("\(folder.name) · \(tabs.count) \(tabs.count == 1 ? "tab" : "tabs")")
        .accessibilityLabel("\(folder.name), pinned group")
    }
}

/// The menu of a pinned group: its tabs (the one on screen checked), then adding the current tab and unpinning.
struct PinnedGroupMenu: View {
    let folder: TabFolder
    let state: BrowserState
    weak var commands: BrowserCommands?

    var body: some View {
        let tabs = state.tabs(inSubtree: folder)
        if tabs.isEmpty {
            Text("No Tabs Yet")
        }
        ForEach(tabs) { tab in
            Button {
                withAnimation(.ikago) { state.select(tab.id) }
            } label: {
                if tab.id == state.activeTabID {
                    Label(tab.displayTitle, systemImage: "checkmark")
                } else if let icon = FaviconCache.shared.cachedImage(pageURL: tab.url, iconURL: tab.faviconURL) {
                    Label { Text(tab.displayTitle) } icon: { Image(nsImage: Self.menuIcon(icon)) }
                } else {
                    Label(tab.displayTitle, systemImage: "globe")
                }
            }
        }
        Divider()
        if let active = state.activeTab, active.folderID != folder.id, !active.pinned {
            Button("Add Current Tab") { withAnimation(.ikago) { state.moveToFolder(active.id, folderID: folder.id) } }
        }
        Button("Unpin Group") { withAnimation(.ikago) { state.setFolderPinned(folder.id, false) } }
    }

    /// Menus draw images at their own size: a 16 pt copy of the icon.
    private static func menuIcon(_ image: NSImage) -> NSImage {
        let copy = image.copy() as? NSImage ?? image
        copy.size = NSSize(width: 16, height: 16)
        return copy
    }
}

extension View {
    /// Tabs dropped on a pinned group join it.
    func pinnedGroupDrop(folder: TabFolder, state: BrowserState, chrome: ChromeModel, targeted: Binding<Bool>) -> some View {
        onDrop(of: [.ikagoTab], isTargeted: targeted) { providers in
            guard let provider = providers.first else { return false }
            let target = folder.id
            TabDrag.load(provider, into: state) { id in
                chrome.endTabDrag()
                withAnimation(.ikago) { state.moveToFolder(id, folderID: target) }
            }
            return true
        }
    }
}
