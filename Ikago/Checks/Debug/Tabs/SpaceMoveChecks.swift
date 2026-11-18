#if DEBUG
import Foundation

/// Moving tabs and groups between Spaces, and batch bookmark edits (the Bookmarks page's selection).
@MainActor
enum SpaceMoveChecks {
    static func run() {
        var failures = 0
        func check(_ value: Bool, _ title: String) {
            print("IKTEST spacemove \(value ? "PASS" : "FAIL") \(title)")
            if !value { failures += 1 }
        }
        let root = FileManager.default.temporaryDirectory.appending(path: "IkagoSpaceMove-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let state = BrowserState(store: SessionStore(directory: root))
        let home = state.activeSpaceID
        let shared = state.createSpace(name: "Shared", symbol: "star", isolated: false)
        let isolated = state.createSpace(name: "Isolated", symbol: "lock", isolated: true)
        state.switchSpace(home)

        // A group with a nested group and tabs in both.
        let outer = state.createFolder(named: "Outer")
        let inner = state.createFolder(named: "Inner", parentID: outer.id)
        let a = state.newTab(url: "https://a.example", select: false, folderID: outer.id)!
        let b = state.newTab(url: "https://b.example", select: false, folderID: inner.id)!
        let loose = state.newTab(url: "https://loose.example")!
        state.moveFolder(outer.id, toSpace: shared.id)
        check(state.folders.filter { [outer.id, inner.id].contains($0.id) }.allSatisfy { $0.spaceID == shared.id },
              "a group moves with the groups inside it")
        check(state.folders.first { $0.id == outer.id }?.parentID == nil
              && state.folders.first { $0.id == inner.id }?.parentID == outer.id, "nesting is kept")
        check(a.spaceID == shared.id && a.folderID == outer.id && b.spaceID == shared.id && b.folderID == inner.id,
              "tabs keep their groups (shared storage moves pages as is)")
        check(state.spaceFolders.isEmpty && state.spaceTabs.map(\.id) == [loose.id], "the old Space keeps only its own tabs")

        // Into an isolated Space the pages reopen there, still in their groups.
        state.switchSpace(shared.id)
        state.moveFolder(outer.id, toSpace: isolated.id)
        let moved = state.tabs.filter { $0.spaceID == isolated.id }
        check(Set(moved.map(\.url)) == ["https://a.example", "https://b.example"]
              && moved.first { $0.url == "https://b.example" }?.folderID == inner.id, "isolated move reopens tabs in their groups")
        check(state.tab(a.id) == nil && !state.closed.contains { $0.url == "https://a.example" },
              "reopened tabs leave no closed-tab entry")

        // Several tabs keep their order.
        state.switchSpace(home)
        let c = state.newTab(url: "https://c.example")!, d = state.newTab(url: "https://d.example")!
        state.moveTabs([loose.id, c.id, d.id], toSpace: shared.id)
        check(state.tabs.filter { $0.spaceID == shared.id }.map(\.id) == [loose.id, c.id, d.id], "selected tabs move in order")
        check(state.spaceTabs.isEmpty, "the source Space is empty after moving its tabs")

        // Batch bookmarks.
        for name in ["one", "two", "three", "four"] {
            state.addBookmark(TabItem(url: "https://\(name).example", title: name))
        }
        let folder = state.createBookmarkFolder(named: "Batch")!
        let ids = state.bookmarks.suffix(4).map(\.id)
        state.moveBookmarks(Set(ids.prefix(2)), to: folder.id)
        check(state.bookmarks(in: folder.id).map(\.id) == Array(ids.prefix(2)), "selected bookmarks move together")
        state.removeBookmarks(Set(ids.suffix(3)))
        check(state.bookmarks.map(\.id) == [ids[0]], "selected bookmarks are deleted together; others stay")
        check(state.bookmarkFolders.contains { $0.id == folder.id }, "deleting bookmarks keeps their folder")

        print("IKTEST spacemovechecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }
}
#endif
