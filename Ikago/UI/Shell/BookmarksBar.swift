import SwiftUI

/// A bounded row in the shared top-bar surface; nested folders open native menus.
struct BookmarksBar: View {
    let state: BrowserState
    let chrome: ChromeModel
    weak var commands: BrowserCommands?
    @State private var edges = TabScrollEdges()

    var body: some View {
        let colors = state.barPalette
        HStack(spacing: 5) {
            ChromeButton(symbol: "book", help: "Manage Bookmarks", colors: colors, size: 26) { commands?.openPage(.bookmarks) }
            ScrollView(.horizontal) {
                LazyHStack(spacing: 6) {
                    ForEach(state.bookmarkChildren(of: nil)) { folder in
                        BookmarkFolderMenu(folder: folder, state: state, commands: commands, colors: colors)
                            .font(.system(size: 11.5)).foregroundStyle(colors.text)
                            .padding(.horizontal, 8).frame(height: 26)
                            .bookmarkDrop(state: state, chrome: chrome, folderID: folder.id)
                    }
                    ForEach(state.bookmarks(in: nil)) { bookmark in
                        BookmarkShortcut(bookmark: bookmark, state: state, colors: colors, commands: commands)
                    }
                    if state.bookmarks.isEmpty && state.bookmarkFolders.isEmpty {
                        Text("Save a page with ⌘D, or drop a tab here")
                            .font(.system(size: 11.5)).foregroundStyle(colors.secondary)
                    }
                }
                .padding(.trailing, 6)
            }
            .scrollIndicators(.never)
            .onScrollGeometryChange(for: TabScrollEdges.self) { TabScrollEdges($0) } action: { _, value in edges = value }
            .mask(TabStripEdgeFade(edges: edges))
        }
        .padding(.horizontal, 5).frame(height: 32)
        .environment(\.colorScheme, colors.isDark ? .dark : .light)
        .bookmarkDrop(state: state, chrome: chrome, folderID: nil)
        .contextMenu {
            Button("New Folder…") { commands?.newBookmarkFolder(parentID: nil) }
            Button("Manage Bookmarks…") { commands?.openPage(.bookmarks) }
            Divider()
            Button("Hide Bookmarks Bar") { withAnimation(.ikago) { state.showsBookmarksBar = false } }
        }
        .recordLayout("bookmarks-bar")
    }
}

struct BookmarkShortcut: View {
    let bookmark: Bookmark
    let state: BrowserState
    let colors: Palette
    weak var commands: BrowserCommands?
    var sidebar = false
    @State private var hovering = false

    var body: some View {
        Button { commands?.openBookmark(bookmark, forceNewTab: false) } label: {
            HStack(spacing: 7) {
                FaviconView(pageURL: bookmark.url, iconURL: bookmark.favicon, size: 13)
                Text(bookmark.title).font(.system(size: 12)).lineLimit(1)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: sidebar ? .infinity : 160, alignment: .leading)
            .frame(height: 28).contentShape(Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(colors.text.opacity(0.85))
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(hovering ? colors.hover : .clear))
        .onHover { hovering = $0 }
        .animation(.ikagoQuick, value: hovering)
        .contextMenu { BookmarkContextMenu(bookmark: bookmark, state: state, commands: commands) }
        .draggable(BookmarkDrag(id: bookmark.id))
        .onMiddleClick { commands?.openBookmark(bookmark, forceNewTab: true) }
        .help("\(bookmark.title)\n\(bookmark.url)")
    }
}
