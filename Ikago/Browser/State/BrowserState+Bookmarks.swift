import Foundation

extension BrowserState {
    var showsBookmarksBar: Bool {
        get { browserPreferences.showBookmarksBar ?? false }
        set { browserPreferences.showBookmarksBar = newValue }
    }

    var sidebarBookmarksExpanded: Bool {
        get { browserPreferences.sidebarBookmarksExpanded ?? false }
        set { browserPreferences.sidebarBookmarksExpanded = newValue }
    }

    func bookmarkChildren(of folderID: String?) -> [BookmarkFolder] {
        bookmarkFolders.filter { $0.parentID == folderID }
    }

    func bookmarks(in folderID: String?) -> [Bookmark] { bookmarks.filter { $0.folderID == folderID } }

    @discardableResult
    func createBookmarkFolder(named name: String, parentID: String? = nil) -> BookmarkFolder? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, bookmarkFolders.count < 500,
              parentID == nil || bookmarkFolders.contains(where: { $0.id == parentID }),
              bookmarkFolderDepth(parentID) < 30 else { return nil }
        let folder = BookmarkFolder(name: String(name.prefix(60)), parentID: parentID)
        bookmarkFolders.append(folder)
        scheduleSave()
        return folder
    }

    func renameBookmarkFolder(_ id: String, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let index = bookmarkFolders.firstIndex(where: { $0.id == id }) else { return }
        bookmarkFolders[index].name = String(name.prefix(60))
        scheduleSave()
    }

    /// Removing a folder keeps every bookmark and lifts its immediate children one level.
    func removeBookmarkFolder(_ id: String) {
        guard let folder = bookmarkFolders.first(where: { $0.id == id }) else { return }
        for index in bookmarks.indices where bookmarks[index].folderID == id { bookmarks[index].folderID = folder.parentID }
        for index in bookmarkFolders.indices where bookmarkFolders[index].parentID == id { bookmarkFolders[index].parentID = folder.parentID }
        bookmarkFolders.removeAll { $0.id == id }
        scheduleSave()
    }

    func moveBookmark(_ id: String, to folderID: String?) {
        guard let index = bookmarks.firstIndex(where: { $0.id == id }),
              folderID == nil || bookmarkFolders.contains(where: { $0.id == folderID }) else { return }
        bookmarks[index].folderID = folderID
        scheduleSave()
    }

    func removeBookmark(_ id: String) {
        bookmarks.removeAll { $0.id == id }
        scheduleSave()
    }

    func updateBookmark(_ id: String, title: String, url: String, folderID: String?) {
        guard AddressResolver.isWebURL(url), !title.isEmpty,
              let index = bookmarks.firstIndex(where: { $0.id == id }),
              folderID == nil || bookmarkFolders.contains(where: { $0.id == folderID }) else { return }
        bookmarks[index].title = String(title.prefix(512))
        if bookmarks[index].url != url { bookmarks[index].favicon = nil }
        bookmarks[index].url = url
        bookmarks[index].folderID = folderID
        scheduleSave()
    }

    /// Paths for the editor's folder picker, with explicit root membership for older bookmarks.
    var bookmarkFolderChoices: [(id: String, path: String)] {
        func children(_ parent: String?, prefix: String) -> [(id: String, path: String)] {
            bookmarkChildren(of: parent).flatMap { folder in
                let path = prefix.isEmpty ? folder.name : prefix + " / " + folder.name
                return [(id: folder.id, path: path)] + children(folder.id, prefix: path)
            }
        }
        return children(nil, prefix: "")
    }

    private func bookmarkFolderDepth(_ id: String?) -> Int {
        var depth = 0, parent = id
        while let id = parent, let folder = bookmarkFolders.first(where: { $0.id == id }), depth < 32 {
            depth += 1; parent = folder.parentID
        }
        return depth
    }
}
