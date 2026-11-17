import SwiftUI

/// Sidebar + Tabs: the bookmarks bar under the address row, like Chrome's. Top-level folders open as menus (their
/// folders as submenus), then the loose bookmarks as chips; the row scrolls sideways when they don't fit. Shown with
/// Show Bookmarks Bar (⇧⌘B), in place of the sidebar's bookmarks drawer.
struct TopBookmarksBar: View {
    let state: BrowserState
    weak var commands: BrowserCommands?
    static let height: CGFloat = 32

    var body: some View {
        let colors = state.palette
        let folders = state.bookmarkChildren(of: nil)
        let loose = state.bookmarks(in: nil)
        ScrollView(.horizontal) {
            HStack(spacing: 2) {
                ForEach(folders) { folder in
                    Menu { FolderMenuContent(state: state, folderID: folder.id, commands: commands) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "folder").font(.system(size: 11))
                            Text(folder.name).font(.system(size: 12)).lineLimit(1)
                        }
                        .padding(.horizontal, 8).frame(maxWidth: 160).frame(height: 26)
                        .contentShape(Rectangle())
                    }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                    .foregroundStyle(colors.text.opacity(0.85))
                    .contextMenu { BookmarkFolderContextMenu(folder: folder, state: state, commands: commands) }
                }
                if !folders.isEmpty && !loose.isEmpty {
                    Rectangle().fill(colors.separator).frame(width: 1, height: 14).padding(.horizontal, 4)
                }
                ForEach(loose) { bookmark in
                    BookmarkShortcut(bookmark: bookmark, state: state, colors: colors, commands: commands).fixedSize()
                }
                if folders.isEmpty && loose.isEmpty {
                    Text("Bookmarks you add appear here").font(.system(size: 12)).foregroundStyle(colors.secondary)
                        .padding(.horizontal, 8)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: Self.height)
        }
        .scrollIndicators(.never)
    }
}

/// A bookmark folder as menu items: its folders as submenus, then its bookmarks.
private struct FolderMenuContent: View {
    let state: BrowserState
    let folderID: String
    weak var commands: BrowserCommands?

    var body: some View {
        let children = state.bookmarkChildren(of: folderID)
        let items = state.bookmarks(in: folderID)
        ForEach(children) { child in
            Menu {
                FolderMenuContent(state: state, folderID: child.id, commands: commands)
            } label: { Label(child.name, systemImage: "folder") }
        }
        if !children.isEmpty && !items.isEmpty { Divider() }
        ForEach(items.prefix(400)) { bookmark in
            Button(bookmark.title.isEmpty ? bookmark.url : String(bookmark.title.prefix(80))) {
                commands?.openBookmark(bookmark, forceNewTab: NSEvent.modifierFlags.contains(.command))
            }
        }
        if children.isEmpty && items.isEmpty { Text("Empty") }
    }
}
