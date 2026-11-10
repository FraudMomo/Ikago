import SwiftUI

struct BookmarksPage: View {
    let state: BrowserState
    weak var commands: BrowserCommands?
    @State private var query = ""
    @State private var folderID: String?

    private var folder: BookmarkFolder? { state.bookmarkFolders.first { $0.id == folderID } }
    private var matches: [Bookmark] {
        state.bookmarks.filter {
            query.isEmpty ? $0.folderID == folderID
                : $0.title.localizedCaseInsensitiveContains(query) || $0.url.localizedCaseInsensitiveContains(query)
        }
    }
    private var folders: [BookmarkFolder] {
        query.isEmpty ? state.bookmarkChildren(of: folderID)
            : state.bookmarkFolders.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        PageScaffold(title: "Bookmarks", colors: state.palette, trailing: AnyView(
            TextField("Search bookmarks", text: $query).textFieldStyle(.roundedBorder).frame(maxWidth: 240))) {
            ViewThatFits(in: .horizontal) {
                HStack { navigation; Spacer(minLength: 12); newFolder }
                VStack(alignment: .leading, spacing: 12) { navigation; newFolder }
            }
            if matches.isEmpty && folders.isEmpty {
                EmptyNote(symbol: "bookmark", text: query.isEmpty ? "Press ⌘D on a page to bookmark it, or drop a tab here" : "No matches")
            }
            PageSection(title: query.isEmpty ? (folder?.name ?? "Bookmarks Bar") : "Search Results",
                        footer: "Shared across Spaces. Drag bookmarks into folders, or right-click to move, edit and organize them.") {
                ForEach(folders) { child in
                    Button { withAnimation(.ikago) { folderID = child.id; query = "" } } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "folder").frame(width: 16).foregroundStyle(state.palette.secondary)
                            Text(child.name).lineLimit(1)
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(.tertiary)
                        }.padding(16).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu { BookmarkFolderContextMenu(folder: child, state: state, commands: commands) }
                    .bookmarkDrop(state: state, chrome: nil, folderID: child.id)
                    PageDivider()
                }
                ForEach(matches) { bookmark in
                    Button { commands?.openBookmark(bookmark, forceNewTab: false) } label: {
                        HStack(spacing: 12) {
                            FaviconView(pageURL: bookmark.url, iconURL: bookmark.favicon)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(bookmark.title).lineLimit(1)
                                Text(bookmark.url).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 4)
                        }.padding(16).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu { BookmarkContextMenu(bookmark: bookmark, state: state, commands: commands) }
                    .draggable(BookmarkDrag(id: bookmark.id))
                    PageDivider()
                }
                if matches.isEmpty && folders.isEmpty { Color.clear.frame(height: 40) }
            }
            .bookmarkDrop(state: state, chrome: nil, folderID: folderID)
        }
        .onChange(of: state.bookmarkFolders) { _, _ in
            if folderID != nil && folder == nil { folderID = nil }
        }
    }

    private var navigation: some View {
        HStack(spacing: 10) {
            if folderID != nil {
                Button { withAnimation(.ikago) { folderID = folder?.parentID; query = "" } } label: {
                    Label("Back", systemImage: "chevron.left")
                }.controlSize(.small)
                Button("All Bookmarks") { folderID = nil; query = "" }.controlSize(.small)
            } else { Text("Organize your saved pages").font(.system(size: 13)).foregroundStyle(.secondary) }
        }
    }

    private var newFolder: some View {
        Button { commands?.newBookmarkFolder(parentID: folderID) } label: { Label("New Folder", systemImage: "folder.badge.plus") }
    }
}
