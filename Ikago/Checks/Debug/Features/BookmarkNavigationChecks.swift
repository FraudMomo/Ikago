#if DEBUG
import AppKit

@MainActor
enum BookmarkNavigationChecks {
    static func run(_ controller: BrowserWindowController) async {
        var failures = 0
        func check(_ value: Bool, _ title: String) {
            print("IKTEST bookmarknavigation \(value ? "PASS" : "FAIL") \(title)")
            if !value { failures += 1 }
        }
        let root = SessionStore.testDirectory.appending(path: "BookmarkNavigationChecks-\(UUID())")
        let state = BrowserState(store: SessionStore(directory: root))
        defer {
            state.saveTask?.cancel()
            try? FileManager.default.removeItem(at: root)
        }
        check(state.showsPinnedGrid, "legacy profile keeps the pinned grid")
        let source = state.newTab(url: "https://example.com/docs?q=one#top")!
        source.title = "Docs"
        state.addBookmark(source)
        let bookmark = state.bookmarks[0]
        check(state.openBookmark(bookmark)?.id == source.id && state.tabs.count == 1, "default reuses exact open page including fragment variants")
        source.url = "https://example.com/account"
        let opened = state.openBookmark(bookmark)!
        check(opened.id != source.id && !opened.pinned && opened.folderID == nil && opened.url == bookmark.url,
              "bookmark opens an ordinary tab and retains the saved URL after source navigation")
        let count = state.tabs.count
        state.browserPreferences.reuseBookmarkTabs = false
        check(state.openBookmark(bookmark)?.id != opened.id && state.tabs.count == count + 1, "always-new mode permits duplicate tabs")
        state.browserPreferences.reuseBookmarkTabs = true
        let forced = state.openBookmark(bookmark, forceNewTab: true)!
        check(forced.id != opened.id, "explicit Open in New Tab overrides reuse")
        check(state.openBookmark(bookmark)?.id == forced.id, "selected matching tab wins among duplicates")
        state.closeTab(forced.id, removingPin: true)
        for tab in state.tabs where tab.id != source.id { state.closeTab(tab.id, removingPin: true) }
        let different = Bookmark(url: "https://example.com/different", title: "Different")
        check(state.matchingBookmarkTab(for: different.url) == nil, "same domain does not match a different path by default")
        state.browserPreferences.bookmarkMatchDomain = true
        check(state.openBookmark(different)?.id == source.id && source.url == "https://example.com/account", "domain reuse switches without navigating the existing page")
        check(state.matchingBookmarkTab(for: "https://notexample.com/") == nil
              && state.matchingBookmarkTab(for: "https://sub.example.com/") == nil, "domain matching requires the exact host")
        let personal = state.activeSpaceID
        _ = state.createSpace(name: "Isolated", symbol: "star", isolated: true)
        let isolated = state.openBookmark(bookmark)!
        check(isolated.spaceID != personal && state.activeSpaceID == isolated.spaceID && state.tabs.count == 2,
              "bookmark never reuses a tab in another Space or website profile")
        state.closeTab(isolated.id, removingPin: true)
        check(state.bookmarks.count == 1, "closing the opened tab keeps the bookmark")
        state.switchSpace(personal)
        state.browserPreferences.showPinnedGrid = false
        state.togglePin(source.id)
        state.saveNow()
        let restored = BrowserState(store: state.store)
        defer { restored.saveTask?.cancel() }
        check(restored.bookmarks == state.bookmarks && restored.browserPreferences == state.browserPreferences
              && restored.pinnedTabs.count == 1, "bookmarks, grid visibility, reuse preference and pins survive session restore")
        do {
            // Removed shortcut metadata is ignored; saved pages and icons survive.
            let legacyData = Data(#"{"id":"legacy","url":"https://example.com","title":"Legacy","favorite":true,"favicon":"https://example.com/icon.png"}"#.utf8)
            let legacy = try JSONDecoder().decode(Bookmark.self, from: legacyData)
            check(legacy.id == "legacy" && legacy.url == "https://example.com" && legacy.favicon == "https://example.com/icon.png",
                  "legacy saved shortcuts decode as ordinary bookmarks without losing icons")
            let encoded = try JSONEncoder().encode(legacy)
            let object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
            check(object?["favorite"] == nil, "removed shortcut metadata is not saved again")
            try state.snapshot().validate()
            check(true, "session with bookmarks passes normal validation")
        } catch { check(false, error.localizedDescription) }
        check(state.openBookmark(Bookmark(url: "javascript:alert(1)", title: "Invalid")) == nil, "non-web bookmarks are rejected")
        check(BrowserState.pageKey("https://example.com/a?q=1") != BrowserState.pageKey("https://example.com/a?q=2"),
              "different query strings remain separate pages")

        // Exercise the actual window command while address editing, then restore its fixture.
        let original = controller.state.snapshot()
        defer { controller.state.apply(original) }
        controller.state.browserPreferences.reuseBookmarkTabs = false
        controller.showCommandPalette(newTab: false)
        controller.openBookmark(Bookmark(url: "https://bookmark-command.invalid/", title: "Bookmark command"))
        check(!controller.isEditingAddress && controller.state.activeTab?.url == "https://bookmark-command.invalid/"
              && controller.state.activeTab?.pinned == false, "bookmark command dismisses address editing and creates a regular tab")
        print("IKTEST bookmarknavigationchecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }
}
#endif
