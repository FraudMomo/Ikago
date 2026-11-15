import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Bookmark menus
struct BookmarkContextMenu: View {
    let bookmark: Bookmark
    let state: BrowserState
    weak var commands: BrowserCommands?

    var body: some View {
        Button("Open in New Tab") { commands?.openBookmark(bookmark, forceNewTab: true) }
        Button("Open in Private Window") { commands?.openInPrivateWindow(bookmark.url) }
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

// MARK: - Bookmark drop
struct BookmarkDrag: Codable, Transferable {
    let id: String
    static var transferRepresentation: some TransferRepresentation { CodableRepresentation(contentType: .ikagoBookmark) }
}

extension UTType { static let ikagoBookmark = UTType(exportedAs: "app.ikago.bookmark") }

extension View {
    /// Saving an open tab here keeps the tab alive.
    func bookmarkDrop(state: BrowserState, chrome: ChromeModel?, folderID: String?) -> some View {
        onDrop(of: [.ikagoBookmark, .ikagoTab], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            if provider.hasItemConformingToTypeIdentifier(UTType.ikagoTab.identifier) {
                TabDrag.load(provider, into: nil) { id in
                    chrome?.endTabDrag()
                    guard let tab = state.tab(id), AddressResolver.isWebURL(tab.url) else { return }
                    state.addBookmark(tab)
                    if let bookmark = state.bookmarks.first(where: { $0.url == tab.url }) { state.moveBookmark(bookmark.id, to: folderID) }
                }
            } else {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.ikagoBookmark.identifier) { data, _ in
                    guard let data, let drag = try? JSONDecoder().decode(BookmarkDrag.self, from: data) else { return }
                    Task { @MainActor in state.moveBookmark(drag.id, to: folderID) }
                }
            }
            return true
        }
    }
}

// MARK: - Bookmark shortcut
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
        .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(hovering ? colors.hover : .clear))
        .onHover { hovering = $0 }
        .animation(.ikagoQuick, value: hovering)
        .contextMenu { BookmarkContextMenu(bookmark: bookmark, state: state, commands: commands) }
        .draggable(BookmarkDrag(id: bookmark.id))
        .onMiddleClick { commands?.openBookmark(bookmark, forceNewTab: true) }
        .help("\(bookmark.title)\n\(bookmark.url)")
    }
}
