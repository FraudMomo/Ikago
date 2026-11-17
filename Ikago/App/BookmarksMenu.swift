import AppKit

/// The menu bar's Bookmarks menu lists the bookmarks like Safari and Chrome do: after its own commands, the top-level
/// folders as submenus (built when opened) and then the loose bookmarks, each with its site's icon.
@MainActor
final class BookmarksMenu: NSObject, NSMenuDelegate {
    static let shared = BookmarksMenu()
    /// Items above this tag are the menu's own commands; everything after is rebuilt each time it opens.
    private static let listTag = 7_301
    private static let perMenuLimit = 400

    private var state: BrowserState? {
        let window = [NSApp.keyWindow, NSApp.mainWindow].compactMap { $0?.windowController as? BrowserWindowController }.first
            ?? BrowserWindows.all.first
        return window?.state
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if let start = menu.items.firstIndex(where: { $0.tag == Self.listTag }) {
            for _ in start..<menu.items.count { menu.removeItem(at: start) }
        }
        guard let state else { return }
        let marker = NSMenuItem.separator()
        marker.tag = Self.listTag
        menu.addItem(marker)
        if state.bookmarks.isEmpty {
            let empty = NSMenuItem(title: "No Bookmarks", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return
        }
        fill(menu, folder: nil, state: state)
    }

    /// One folder's contents: its folders first (as submenus filled when they open), then its bookmarks.
    private func fill(_ menu: NSMenu, folder: String?, state: BrowserState) {
        let known = Set(state.bookmarkFolders.map(\.id))
        for child in state.bookmarkFolders where child.parentID == folder {
            let item = NSMenuItem(title: child.name, action: nil, keyEquivalent: "")
            item.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
            let submenu = NSMenu(title: child.name)
            submenu.delegate = self
            submenu.identifier = NSUserInterfaceItemIdentifier(child.id)
            item.submenu = submenu
            menu.addItem(item)
        }
        // A bookmark whose folder no longer exists shows at the top level.
        let items = state.bookmarks.filter { bookmark in
            folder == nil ? bookmark.folderID.map { !known.contains($0) } ?? true : bookmark.folderID == folder
        }
        if !items.isEmpty, menu.items.contains(where: { $0.submenu != nil }) { menu.addItem(.separator()) }
        for bookmark in items.prefix(Self.perMenuLimit) {
            let title = bookmark.title.isEmpty ? bookmark.url : bookmark.title
            let item = NSMenuItem(title: String(title.prefix(80)), action: #selector(BrowserWindowController.openBookmarkFromMenu(_:)),
                                  keyEquivalent: "")
            item.representedObject = bookmark.id
            item.toolTip = bookmark.url
            item.image = icon(for: bookmark)
            menu.addItem(item)
        }
        if items.count > Self.perMenuLimit {
            menu.addItem(.separator())
            menu.addItem(withTitle: "Show All Bookmarks…", action: #selector(BrowserWindowController.showBookmarks(_:)), keyEquivalent: "")
        }
        if menu.items.isEmpty {
            let empty = NSMenuItem(title: "Empty", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
    }

    private func icon(for bookmark: Bookmark) -> NSImage {
        let image = FaviconCache.shared.cachedImage(pageURL: bookmark.url, iconURL: bookmark.favicon.flatMap(URL.init(string:)))
            ?? NSImage(systemSymbolName: "globe", accessibilityDescription: nil) ?? NSImage()
        let sized = image.copy() as? NSImage ?? image
        sized.size = NSSize(width: 16, height: 16)
        return sized
    }
}

/// Submenus (one per folder) fill themselves when they open.
extension BookmarksMenu {
    func menuWillOpen(_ menu: NSMenu) {
        guard let id = menu.identifier?.rawValue, let state, state.bookmarkFolders.contains(where: { $0.id == id }) else { return }
        menu.removeAllItems()
        fill(menu, folder: id, state: state)
    }
}
