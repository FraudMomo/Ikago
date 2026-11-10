#if DEBUG
import AppKit

/// Folder persistence and the geometry of the two bookmark surfaces, using disposable state.
@MainActor
enum BookmarkBarChecks {
    static func seed(_ browser: BrowserWindowController) {
        let state = browser.state
        browser.dismissCommandPalette()
        state.tabs = []; state.folders = []; state.splits = []; state.bookmarks = []; state.bookmarkFolders = []
        _ = state.newTab(url: InternalPage.bookmarks.url)
        for page in [InternalPage.history, .downloads, .settings] {
            if let tab = state.newTab(url: page.url, select: false) { state.togglePin(tab.id) }
        }
        let work = state.createBookmarkFolder(named: "Research")!
        let docs = state.createBookmarkFolder(named: "Documentation", parentID: work.id)!
        _ = state.createBookmarkFolder(named: "Reading")
        state.bookmarks = [
            Bookmark(url: "https://developer.apple.com", title: "Apple Developer"),
            Bookmark(url: "https://webkit.org", title: "WebKit"),
            Bookmark(url: "https://swift.org", title: "Swift", folderID: work.id),
            Bookmark(url: "https://developer.apple.com/documentation", title: "Documentation", folderID: docs.id),
            Bookmark(url: "https://wikipedia.org", title: "Wikipedia")
        ]
        state.showsBookmarksBar = true
        state.showsTopBarEssentials = true
        state.showsTopBarPins = true
    }

    static func run(_ browser: BrowserWindowController) async {
        var failures = 0
        func check(_ value: Bool, _ title: String) {
            print("IKTEST bookmarkbar \(value ? "PASS" : "FAIL") \(title)")
            if !value { failures += 1 }
        }
        let directory = SessionStore.testDirectory.appending(path: "BookmarkFolderChecks")
        let store = SessionStore(directory: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = BrowserState(store: store)
        check(model.bookmarkFolders.isEmpty && !model.showsBookmarksBar, "older profiles keep bookmarks at the root and the bar opt-in")
        let parent = model.createBookmarkFolder(named: "Work")!
        let child = model.createBookmarkFolder(named: "Docs", parentID: parent.id)!
        let grandchild = model.createBookmarkFolder(named: "API", parentID: child.id)!
        model.bookmarks = [Bookmark(url: "https://example.org/docs", title: "Docs", folderID: child.id)]
        model.showsBookmarksBar = true; model.sidebarBookmarksExpanded = true
        model.showsTopBarEssentials = false
        model.saveNow()
        let restored = BrowserState(store: store)
        check(restored.bookmarkFolders == model.bookmarkFolders && restored.bookmarks == model.bookmarks,
              "nested folders and bookmark membership survive relaunch")
        check(restored.showsBookmarksBar && restored.sidebarBookmarksExpanded && !restored.showsTopBarEssentials,
              "independent surface preferences survive relaunch")
        model.removeBookmarkFolder(child.id)
        check(model.bookmarks.first?.folderID == parent.id
              && model.bookmarkFolders.first(where: { $0.id == grandchild.id })?.parentID == parent.id,
              "removing a folder retains bookmarks and nested folders one level up")
        model.moveBookmark(model.bookmarks[0].id, to: nil)
        check(model.bookmarks(in: nil).count == 1, "bookmarks can move back onto the bar")
        var invalid = model.snapshot()
        invalid.bookmarkFolders = [BookmarkFolder(id: "cycle", name: "Cycle", parentID: "cycle")]
        check((try? invalid.validate()) == nil, "cyclic folder trees cannot be persisted")
        var old = model.snapshot(); old.bookmarkFolders = nil
        check((try? old.validate()) != nil, "old sessions without bookmark folder metadata remain valid")

        let original = browser.state.snapshot(), size = browser.window?.contentView?.frame.size
        defer {
            browser.state.apply(original)
            if let size { browser.window?.setContentSize(size) }
        }
        seed(browser)
        let state = browser.state
        state.useGlass = false; state.tabLayout = .horizontal
        state.topTabStyle = .separate
        for floating in [false, true] {
            state.barRounded = floating
            for width in [1100.0, 420.0] {
                browser.window?.setContentSize(NSSize(width: width, height: 750))
                try? await Task.sleep(for: .milliseconds(500))
                let bar = LayoutChecks.frames["bookmarks-bar"]
                print("IKTEST bookmark bounds width=\(width) floating=\(floating) bar=\(String(describing: bar)) row=\(String(describing: LayoutChecks.frames["connected-tab-row"]))")
                check(bar.map { $0.minX >= 0 && $0.maxX <= width + 1 && abs($0.height - 32) < 1 } == true,
                      "bookmark bar stays bounded at \(Int(width)) pt, floating=\(floating)")
                let tabRow = LayoutChecks.frames["connected-tab-row"]
                check(bar.flatMap { bar in tabRow.map { abs(bar.minY - $0.maxY) < 1 } } == true,
                      "bookmarks touch the tab row inside one surface")
                if floating {
                    check(browser.activeController?.topInset == state.floatingContentInset
                          && state.floatingContentInset >= state.topBarAccessoryHeight,
                          "floating page content starts below the bookmark bar")
                }
            }
        }
        state.showsTopBarEssentials = false
        try? await Task.sleep(for: .milliseconds(500))
        check(state.topBarAccessoryHeight == 32, "pinned tabs reserve no accessory row height")
        state.showsBookmarksBar = false
        check(state.topBarAccessoryHeight == 0, "hiding bookmarks returns accessory height to the page")
        state.showsBookmarksBar = true; state.tabLayout = .vertical
        state.sidebarBookmarksExpanded = true
        browser.window?.setContentSize(NSSize(width: 1100, height: 750))
        try? await Task.sleep(for: .milliseconds(500))
        check(LayoutChecks.frames["bookmarks-drawer"].map { $0.maxY <= 751 && $0.width <= state.sidebarWidth } == true,
              "expanded sidebar bookmarks stay inside the sidebar")
        state.tabLayout = .horizontal
        check(!state.presentsSidebarPinGrid, "top-bar tab overview uses rows rather than sidebar essentials grids")
        print("IKTEST bookmarkbarchecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }
}
#endif
