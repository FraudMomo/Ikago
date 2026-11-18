import AppKit
import SwiftUI

// MARK: - Bookmarks page

struct BookmarksPage: View {
    let state: BrowserState
    weak var commands: BrowserCommands?
    @State private var query = ""
    @State private var folderID: String?
    /// Rows drawn so far: big folders and searches show 200 at a time instead of building thousands of rows at once.
    @State private var limit = Self.pageSize
    private static let pageSize = 200
    /// Bookmarks picked for a batch action. Shift-click picks a range, ⌘-click one more; in Select mode a plain
    /// click picks too. Kept across searches so a search's results can be gathered and removed together.
    @State private var selection = Set<String>()
    @State private var anchor: String?
    @State private var selecting = false
    @State private var confirmingDelete = false

    private var folder: BookmarkFolder? { state.bookmarkFolders.first { $0.id == folderID } }
    private var matches: [Bookmark] {
        guard !query.isEmpty else { return state.bookmarks(in: folderID) }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return state.bookmarks.filter { $0.title.range(of: query, options: options) != nil || $0.url.range(of: query, options: options) != nil }
    }
    private var folders: [BookmarkFolder] {
        query.isEmpty ? state.bookmarkChildren(of: folderID)
            : state.bookmarkFolders.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        // Worked out once per update: the filters run over every bookmark.
        let matches = matches, folders = folders
        return PageScaffold(title: "Bookmarks", colors: state.palette, trailing: AnyView(
            TextField("Search bookmarks", text: $query).textFieldStyle(.roundedBorder).frame(maxWidth: 240))) {
            if selecting || !selection.isEmpty {
                selectionBar(matches)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack { navigation; Spacer(minLength: 12); selectButton(matches); newFolder }
                    VStack(alignment: .leading, spacing: 12) { navigation; HStack { selectButton(matches); newFolder } }
                }
            }
            if matches.isEmpty && folders.isEmpty {
                EmptyNote(symbol: "bookmark", text: query.isEmpty ? "Press ⌘D on a page to bookmark it, or drop a tab here" : "No matches")
            }
            PageSection(title: query.isEmpty ? (folder?.name ?? "Bookmarks Bar") : "Search Results",
                        footer: "Shared across Spaces. Drag bookmarks into folders, or right-click to move, edit and organize them. Shift-click or ⌘-click to pick several.") {
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
                ForEach(matches.prefix(limit)) { bookmark in
                    let picked = selection.contains(bookmark.id)
                    Button { click(bookmark, in: matches) } label: {
                        HStack(spacing: 12) {
                            if selecting || !selection.isEmpty {
                                Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 15))
                                    .foregroundStyle(picked ? state.palette.accent : state.palette.tertiary)
                                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                            }
                            FaviconView(pageURL: bookmark.url, iconURL: bookmark.favicon)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(bookmark.title).lineLimit(1)
                                Text(bookmark.url).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 4)
                        }.padding(16).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .tabSelectionTint(picked, colors: state.palette)
                    .contextMenu {
                        if picked && selection.count > 1 { batchMenu } else {
                            BookmarkContextMenu(bookmark: bookmark, state: state, commands: commands)
                        }
                    }
                    .draggable(BookmarkDrag(id: bookmark.id))
                    PageDivider()
                }
                if matches.count > limit {
                    Button { limit += Self.pageSize } label: {
                        Text("Show \(min(Self.pageSize, matches.count - limit)) More of \(matches.count - limit)")
                            .frame(maxWidth: .infinity).padding(14).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).foregroundStyle(state.palette.secondary)
                }
                if matches.isEmpty && folders.isEmpty { Color.clear.frame(height: 40) }
            }
            .bookmarkDrop(state: state, chrome: nil, folderID: folderID)
        }
        .onChange(of: query) { _, _ in limit = Self.pageSize }
        .onChange(of: folderID) { _, _ in limit = Self.pageSize; selection = []; anchor = nil }
        .onChange(of: state.bookmarkFolders) { _, _ in
            if folderID != nil && folder == nil { folderID = nil }
        }
        .onChange(of: state.bookmarks) { _, bookmarks in
            // Bookmarks removed elsewhere (the bar, the drawer, another window) leave the selection.
            let ids = Set(bookmarks.map(\.id))
            if !selection.isSubset(of: ids) { selection.formIntersection(ids) }
        }
        .alert("Delete \(selection.count) \(selection.count == 1 ? "Bookmark" : "Bookmarks")?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) { deleteSelection() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone. Folders and open tabs are not affected.")
        }
    }

    // MARK: Selection

    /// Finder's rules: Shift picks every bookmark from the last one clicked, ⌘ adds or removes one; a plain click
    /// opens the bookmark and ends the selection, or picks it while Select is on.
    private func click(_ bookmark: Bookmark, in order: [Bookmark]) {
        let flags = NSEvent.modifierFlags
        withAnimation(.ikagoQuick) {
            if flags.contains(.shift) {
                let ids = order.map(\.id)
                let start = anchor.flatMap { ids.firstIndex(of: $0) } ?? ids.firstIndex(of: bookmark.id)
                if let start, let end = ids.firstIndex(of: bookmark.id) {
                    selection.formUnion(ids[min(start, end)...max(start, end)])
                }
                if anchor == nil { anchor = bookmark.id }
            } else if flags.contains(.command) || selecting {
                if selection.remove(bookmark.id) == nil { selection.insert(bookmark.id) }
                anchor = bookmark.id
            } else {
                selection = []
                anchor = bookmark.id
                commands?.openBookmark(bookmark, forceNewTab: false)
            }
        }
    }

    private func selectButton(_ matches: [Bookmark]) -> some View {
        Button { withAnimation(.ikagoQuick) { selecting = true } } label: { Label("Select", systemImage: "checkmark.circle") }
            .disabled(matches.isEmpty)
            .help("Pick bookmarks to move or delete together. Shift-click picks a range, ⌘-click one more.")
    }

    private func selectionBar(_ matches: [Bookmark]) -> some View {
        let all = Set(matches.map(\.id))
        let allPicked = !all.isEmpty && all.isSubset(of: selection)
        return HStack(spacing: 10) {
            Text(selection.isEmpty ? "Click bookmarks to select them" : "\(selection.count) selected")
                .font(.system(size: 13)).foregroundStyle(.secondary).monospacedDigit()
            Spacer(minLength: 12)
            Button(allPicked ? "Deselect All" : "Select All (\(matches.count))") {
                withAnimation(.ikagoQuick) { if allPicked { selection.subtract(all) } else { selection.formUnion(all) } }
            }
            .disabled(matches.isEmpty)
            Menu("Move To") { moveTargets }
                .fixedSize().disabled(selection.isEmpty)
            Button("Delete…", role: .destructive) { confirmingDelete = true }
                .disabled(selection.isEmpty)
            Button("Done") { withAnimation(.ikagoQuick) { selection = []; anchor = nil; selecting = false } }
                .keyboardShortcut(.cancelAction)
        }
        .controlSize(.small)
    }

    @ViewBuilder private var moveTargets: some View {
        Button("Bookmarks Bar") { moveSelection(to: nil) }
        ForEach(state.bookmarkFolderChoices, id: \.id) { choice in
            Button(choice.path) { moveSelection(to: choice.id) }
        }
    }

    /// The menu for a right-click on one of several selected bookmarks: it acts on all of them.
    @ViewBuilder private var batchMenu: some View {
        Button("Open \(selection.count) in New Tabs") {
            for bookmark in state.bookmarks where selection.contains(bookmark.id) { commands?.openBookmark(bookmark, forceNewTab: true) }
        }
        Menu("Move \(selection.count) to Folder") { moveTargets }
        Divider()
        Button("Delete \(selection.count) Bookmarks…", role: .destructive) { confirmingDelete = true }
    }

    private func moveSelection(to folder: String?) {
        withAnimation(.ikago) { state.moveBookmarks(selection, to: folder) }
        selection = []; anchor = nil
    }

    private func deleteSelection() {
        withAnimation(.ikago) { state.removeBookmarks(selection) }
        selection = []; anchor = nil; selecting = false
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

// MARK: - Bookmark editor

struct BookmarkEditor: View {
    let state: BrowserState
    let bookmark: Bookmark
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var address: String
    @State private var folderID: String

    init(state: BrowserState, bookmark: Bookmark) {
        self.state = state; self.bookmark = bookmark
        _title = State(initialValue: bookmark.title)
        _address = State(initialValue: bookmark.url)
        _folderID = State(initialValue: bookmark.folderID ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ModalHeading(title: "Edit Bookmark", colors: state.palette) { dismiss() }
            TextField("Title", text: $title).modalInput(state.palette)
            TextField("https://example.com", text: $address).modalInput(state.palette)
            Picker("Folder", selection: $folderID) {
                Text("Bookmarks Bar").tag("")
                ForEach(state.bookmarkFolderChoices, id: \.id) { choice in Text(choice.path).tag(choice.id) }
            }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                    .buttonStyle(ModalButtonStyle(colors: state.palette))
                Spacer()
                Button("Save") {
                    state.updateBookmark(bookmark.id, title: title, url: address, folderID: folderID.isEmpty ? nil : folderID)
                    dismiss()
                }
                .buttonStyle(ModalButtonStyle(colors: state.palette, primary: true))
                .disabled(!AddressResolver.isWebURL(address) || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .modalCard(state.palette, width: 380)
    }
}
