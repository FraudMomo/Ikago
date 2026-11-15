import SwiftUI

/// Expands upward from the sidebar's bottom; the tab list retains its own scroll area.
struct SidebarBookmarksDrawer: View {
    let state: BrowserState
    let chrome: ChromeModel
    weak var commands: BrowserCommands?
    @State private var expandedFolders: Set<String> = []

    var body: some View {
        VStack(spacing: 4) {
            Rectangle().fill(state.palette.separator).frame(height: 1)
            if state.sidebarBookmarksExpanded {
                SidebarScrollView(chrome: chrome) {
                    SidebarBookmarkTree(state: state, chrome: chrome, parentID: nil,
                                        expanded: $expandedFolders, commands: commands)
                    if state.bookmarks.isEmpty && state.bookmarkFolders.isEmpty {
                        Text("Save a page with ⌘D, or drop a tab here")
                            .font(.system(size: 12)).foregroundStyle(state.palette.secondary)
                            .frame(maxWidth: .infinity).padding(12)
                    }
                }
                .frame(idealHeight: 180, maxHeight: 220)
                .bookmarkDrop(state: state, chrome: chrome, folderID: nil)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            HStack(spacing: 4) {
                Button { withAnimation(.ikago) { state.sidebarBookmarksExpanded.toggle() } } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "book").font(.system(size: 12))
                        Text("Bookmarks").font(.system(size: 12, weight: .medium))
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.up").font(.system(size: 8, weight: .semibold))
                            .rotationEffect(.degrees(state.sidebarBookmarksExpanded ? 180 : 0))
                    }
                    .padding(.horizontal, 10).frame(height: 32).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(state.sidebarBookmarksExpanded ? "Expanded" : "Collapsed")
                Menu {
                    if let tab = state.activeTab, AddressResolver.isWebURL(tab.url) {
                        Button("Bookmark This Page") { state.addBookmark(tab) }
                    }
                    Button("New Folder…") { commands?.newBookmarkFolder(parentID: nil) }
                    Button("Manage Bookmarks…") { commands?.openPage(.bookmarks) }
                    Divider()
                    Button("Hide Bookmarks") { withAnimation(.ikago) { state.showsBookmarksBar = false } }
                } label: { Image(systemName: "ellipsis").frame(width: 22, height: 28).contentShape(Rectangle()) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .tint(state.palette.secondary)
            }
            .foregroundStyle(state.palette.secondary)
        }
        .recordLayout("bookmarks-drawer")
    }
}

private struct SidebarBookmarkTree: View {
    let state: BrowserState
    let chrome: ChromeModel
    let parentID: String?
    @Binding var expanded: Set<String>
    weak var commands: BrowserCommands?

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 2) {
            ForEach(state.bookmarkChildren(of: parentID)) { folder in
                Button { withAnimation(.ikago) { if !expanded.insert(folder.id).inserted { expanded.remove(folder.id) } } } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "folder").font(.system(size: 12)).frame(width: 13)
                        Text(folder.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.system(size: 8))
                            .rotationEffect(.degrees(expanded.contains(folder.id) ? 90 : 0))
                    }
                    .padding(.horizontal, 8).frame(height: 28).contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundStyle(state.palette.secondary)
                .contextMenu { BookmarkFolderContextMenu(folder: folder, state: state, commands: commands) }
                .bookmarkDrop(state: state, chrome: chrome, folderID: folder.id)
                if expanded.contains(folder.id) {
                    SidebarBookmarkTree(state: state, chrome: chrome, parentID: folder.id, expanded: $expanded, commands: commands)
                        .padding(.leading, 12)
                }
            }
            ForEach(state.bookmarks(in: parentID)) { bookmark in
                BookmarkShortcut(bookmark: bookmark, state: state, colors: state.palette, commands: commands, sidebar: true)
            }
        }
    }
}
