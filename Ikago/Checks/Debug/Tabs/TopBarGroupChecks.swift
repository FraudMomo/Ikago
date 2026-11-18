#if DEBUG
import Foundation

/// Tab groups in the Sidebar + Tabs row (`TopRowEntry`), where groups show (`GroupPlacement`), and hiding a group.
@MainActor
enum TopBarGroupChecks {
    static func run() {
        var failures = 0
        func check(_ value: Bool, _ title: String) {
            print("IKTEST topbargroups \(value ? "PASS" : "FAIL") \(title)")
            if !value { failures += 1 }
        }
        let root = FileManager.default.temporaryDirectory.appending(path: "IkagoTopBarGroups-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let state = BrowserState(store: SessionStore(directory: root))
        state.browserPreferences.sidebarTopTabs = true
        let work = state.createFolder(named: "Work"), inner = state.createFolder(named: "Inner", parentID: work.id)
        let a = state.newTab(url: "https://example.com/a", select: false, folderID: work.id)!
        let b = state.newTab(url: "https://example.com/b", select: false, folderID: inner.id)!
        let loose = state.newTab(url: "https://example.com/loose")!
        func row() -> [String] {
            var seen = Set<String>()
            return TopRowEntry.row(state: state, seen: &seen).map(\.id)
        }
        check(row() == ["chip:" + work.id, a.id, b.id, loose.id] || row() == ["chip:" + work.id, b.id, a.id, loose.id],
              "a chip leads its group's tabs, nested groups included, then the ungrouped tabs")
        state.toggleFolder(work.id)
        check(row() == ["chip:" + work.id, loose.id], "a collapsed group shows its chip only")
        state.select(a.id)
        check(row() == ["chip:" + work.id, a.id, loose.id], "the active tab stays beside its collapsed group's chip")
        state.toggleFolder(work.id)

        state.browserPreferences.groupPlacement = .sidebar
        check(!state.showsGroupsInTopBar && state.showsGroupsInSidebar && row() == [loose.id], "Sidebar keeps groups out of the tab row")
        state.browserPreferences.groupPlacement = .topBar
        check(state.showsGroupsInTopBar && !state.showsGroupsInSidebar, "Tab Row keeps groups out of the icon sidebar")
        state.browserPreferences.groupPlacement = nil
        check(state.showsGroupsInTopBar && state.showsGroupsInSidebar, "both by default")

        // Hiding: saved, asleep, out of the row; selecting a tab of it shows it again.
        state.select(b.id)
        state.hideFolder(work.id)
        check(state.folders.first { $0.id == work.id }?.isClosed == true && a.isHibernating && b.isHibernating, "a hidden group's pages unload")
        check(state.activeTabID == loose.id, "the selection leaves a hidden group")
        check(row() == [loose.id] && state.closedFolders.map(\.id) == [work.id], "a hidden group leaves the tab row and is listed as hidden")
        check(state.tab(a.id) != nil && state.folders.contains { $0.id == inner.id }, "its tabs and inner groups stay saved")
        state.select(b.id)
        check(state.folders.first { $0.id == work.id }?.isClosed == nil, "selecting a tab inside a hidden group shows the group again")
        state.hideFolder(work.id)
        state.reopenFolder(work.id)
        check(state.folders.first { $0.id == work.id }?.isClosed == nil && state.activeTabID.map { [a.id, b.id].contains($0) } == true,
              "showing a group selects one of its tabs")
        // Top Bar options: where pins sit, the edge peek, and the address bar's styles.
        state.sidebarVisible = true
        check(!state.pinsInTabRow, "with the icon sidebar shown, pins sit in it")
        state.browserPreferences.showPinnedGrid = false
        check(state.pinsInTabRow, "with the pinned grid off, pins lead the tab row")
        state.browserPreferences.showPinnedGrid = nil
        state.sidebarVisible = false
        check(!state.pinsInTabRow, "with the sidebar hidden but sliding in at the edge, pins stay in it")
        check(state.sidebarEdgePeek, "the hidden sidebar reveals at the edge by default")
        state.browserPreferences.sidebarEdgePeek = false
        check(!state.sidebarEdgePeek, "the edge reveal can be turned off")
        check(state.pinsInTabRow, "with the sidebar hidden and no edge reveal, pins lead the tab row")
        check(state.tabsAddressStyle == .centered, "the address bar is centred by default")
        let address = TabItem(url: "https://www.example.com/docs/a%20b?x=1")
        check(address.shortAddress == "example.com/docs/a b?x=1", "Full Width shows the address without scheme or www")
        check(TabItem(url: "https://example.com/").shortAddress == "example.com", "a lone trailing slash is dropped")
        print("IKTEST topbargroupchecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }
}
#endif
