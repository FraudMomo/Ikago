import SwiftUI

struct BookmarkContextMenu: View {
    let bookmark: Bookmark
    let state: BrowserState
    weak var commands: BrowserCommands?

    var body: some View {
        Button("Open in New Tab") { commands?.openBookmark(bookmark, forceNewTab: true) }
        Menu("Move to Folder") {
            Button("Bookmarks Bar") { state.moveBookmark(bookmark.id, to: nil) }
            ForEach(state.bookmarkFolderChoices, id: \.id) { choice in
                Button(choice.path) { state.moveBookmark(bookmark.id, to: choice.id) }
            }
        }
        Button("Edit…") { commands?.editBookmark(bookmark) }
        Divider()
        Button("Remove Bookmark", role: .destructive) { withAnimation(.ikago) { state.removeBookmark(bookmark.id) } }
    }
}

struct BookmarkFolderContextMenu: View {
    let folder: BookmarkFolder
    let state: BrowserState
    weak var commands: BrowserCommands?

    var body: some View {
        Button("New Folder Inside…") { commands?.newBookmarkFolder(parentID: folder.id) }
        Button("Rename Folder…") { commands?.renameBookmarkFolder(folder.id) }
        Divider()
        Button("Remove Folder — Keep Bookmarks") { withAnimation(.ikago) { state.removeBookmarkFolder(folder.id) } }
    }
}

/// Native nested menus keep long folder hierarchies off the bar itself.
struct BookmarkFolderMenu: View {
    let folder: BookmarkFolder
    let state: BrowserState
    weak var commands: BrowserCommands?
    var colors: Palette? = nil

    var body: some View {
        let palette = colors ?? state.palette
        Menu {
            ForEach(state.bookmarkChildren(of: folder.id)) { child in
                BookmarkFolderMenu(folder: child, state: state, commands: commands, colors: palette)
            }
            ForEach(state.bookmarks(in: folder.id)) { bookmark in
                Button { commands?.openBookmark(bookmark, forceNewTab: false) } label: { Text(bookmark.title) }
            }
            if state.bookmarkChildren(of: folder.id).isEmpty && state.bookmarks(in: folder.id).isEmpty { Text("Empty Folder") }
            Divider()
            Button("New Folder…") { commands?.newBookmarkFolder(parentID: folder.id) }
            Button("Manage Bookmarks…") { commands?.openPage(.bookmarks) }
        } label: {
            Label(folder.name, systemImage: "folder")
                .lineLimit(1).frame(maxWidth: 150)
        }
        .menuStyle(.borderlessButton).fixedSize()
        .foregroundStyle(palette.text).tint(palette.text)
        .contextMenu { BookmarkFolderContextMenu(folder: folder, state: state, commands: commands) }
    }
}
