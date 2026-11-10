#if DEBUG
import AppKit

/// Closed tab groups and top-tab compaction.
@MainActor
enum TopLayoutFeatureChecks {
    static func run(_ controller: BrowserWindowController) async {
        var failures = 0
        func check(_ value: Bool, _ title: String) {
            print("IKTEST toplayout \(value ? "PASS" : "FAIL") \(title)")
            if !value { failures += 1 }
        }
        let state = controller.state, original = state.snapshot()
        defer { state.apply(original) }
        state.tabLayout = .horizontal
        let folder = state.createFolder(named: "Closable")
        let members = (0..<3).compactMap { state.newTab(url: "https://group.invalid/\($0)", select: false, folderID: folder.id) }
        let loose = state.newTab(url: "https://loose.invalid/", select: false)
        if let first = members.first { state.select(first.id) }
        // Let the new background tabs start loading before closing their group.
        try? await Task.sleep(for: .milliseconds(800))
        let startedBefore = members.filter { controller.content.controller(for: $0.id)?.page != nil }.count
        controller.closeGroup(folder.id)
        try? await Task.sleep(for: .milliseconds(200))
        let closed = state.folders.first { $0.id == folder.id }
        check(closed?.isClosed == true && !state.stripFolders.contains { $0.id == folder.id }
              && state.closedFolders.contains { $0.id == folder.id }, "closing a group takes it out of the strip")
        check(state.activeTab?.folderID != folder.id, "closing the active group moves selection off it")
        check(!state.navigationOrder.contains { $0.folderID == folder.id }, "next/previous tab skips the closed group")
        // Also close a group whose tabs were opened a moment ago (background loading still pending).
        let quick = state.createFolder(named: "Quick")
        let fresh = (0..<2).compactMap { state.newTab(url: "https://fresh.invalid/\($0)", select: false, folderID: quick.id) }
        controller.closeGroup(quick.id)
        try? await Task.sleep(for: .milliseconds(600))
        check(fresh.allSatisfy { controller.content.controller(for: $0.id)?.page == nil }, "a group closed right after opening its tabs stays unloaded")
        let stillLoaded = members.filter { controller.content.controller(for: $0.id)?.page != nil }.count
        check(startedBefore > 0 && stillLoaded == 0, "the closed group's pages unload (\(startedBefore) started, \(stillLoaded) still loaded)")
        check(members.allSatisfy { member in state.tabs.contains { $0.id == member.id } }, "closed group tabs stay saved")
        state.select(members[1].id)
        check(state.folders.first { $0.id == folder.id }?.isClosed != true && state.activeTabID == members[1].id,
              "selecting a closed group's tab reopens the group")
        controller.closeGroup(folder.id)
        state.reopenFolder(folder.id)
        check(state.stripFolders.contains { $0.id == folder.id } && state.activeTab?.folderID == folder.id,
              "reopening shows the group and selects its first tab")
        do {
            let data = try JSONEncoder().encode(state.snapshot())
            let restored = try JSONDecoder().decode(Session.self, from: data)
            check(restored.folders?.contains { $0.id == folder.id } ?? true, "sessions with group state round-trip")
        } catch { check(false, "session encoding: \(error)") }
        _ = loose

        // Compaction: readable down to 120 pt, then favicon-wide inactive tabs beside a 120 pt active tab.
        let tabs = (0..<30).map { TabItem(url: "https://compact.invalid/\($0)", title: "Tab \($0)", spaceID: state.activeSpaceID) }
        let items = tabs.map(TabListItem.tab)
        let roomy = TabStripLayout(items: Array(items.prefix(4)), available: 1000, maximumTab: 280, activeID: tabs[0].id, minimumInactive: 34)
        check(tabs.prefix(4).allSatisfy { roomy.width(of: $0) >= 240 && roomy.width(of: $0) <= 280 }, "a few Compact tabs share a wide width")
        let crowded = TabStripLayout(items: items, available: 1100, maximumTab: 280, activeID: tabs[0].id, minimumInactive: 34)
        check(crowded.width(of: tabs[0]) == TabStripLayout.minTab && tabs.dropFirst().allSatisfy { crowded.width(of: $0) < TabStripLayout.iconOnlyWidth }
              && crowded.compact, "a crowded strip compacts inactive tabs and keeps the active tab readable")
        let separate = TabStripLayout(items: Array(items.prefix(3)), available: 900, maximumTab: .greatestFiniteMagnitude,
                                      activeID: tabs[0].id, minimumInactive: 40)
        check(abs(separate.natural - 900) <= 3, "Separate tabs fill the row (natural \(separate.natural))")
        let full = TabStripLayout(items: items, available: 300, maximumTab: 280, activeID: tabs[0].id, minimumInactive: 34)
        check(full.natural > 300 && tabs.dropFirst().allSatisfy { full.width(of: $0) == 34 }, "past the minimum the strip scrolls")
        let legacy = TabStripLayout(items: items, available: 1100)
        check(tabs.allSatisfy { legacy.width(of: $0) == TabStripLayout.minTab }, "without a compact minimum tabs stay readable and scroll")
        print("IKTEST toplayoutfeaturechecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }
}
#endif
