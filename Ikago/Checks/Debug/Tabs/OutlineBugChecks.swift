#if DEBUG
import AppKit

/// The sidebar list's reported drag bugs, each driven through the outline's own drag path with a pretend drag (the real
/// pointer is never moved), with window shots before, during (the gap open) and after when `IKAGO_SHOTS` names a folder:
/// 1. a tab or group dropped just above a group lands above it, not inside that group or the open group above;
/// 2. a tab dragged out of a group looks like a loose row (no card, no indent);
/// 3. tabs dragged into and out of groups over and over, nested ones too, never crash and the list keeps following;
/// 4. among the groups at the top, a row dropped between two groups lands between them and can be dragged out again.
@MainActor
enum OutlineBugChecks {
    /// `rail`: the icon sidebar's list.
    static func run(_ browser: BrowserWindowController, rail: Bool = false) async {
        var failures = 0
        let name = rail ? "railbug" : "outlinebug"
        let state = browser.state
        var rigForDetail: OutlineDragRig?
        func check(_ value: Bool, _ title: String) {
            print("IKTEST \(name) \(value ? "PASS" : "FAIL") \(title)")
            if !value {
                failures += 1
                if let rig = rigForDetail { print("IKTEST \(name) rows now: \(rig.summary())") }
            }
        }
        let saved = (state.browserPreferences.sidebarCompact, state.sidebarVisible,
                     state.browserPreferences.sidebarTopTabs, state.browserPreferences.showPinnedGrid)
        defer {
            state.browserPreferences.sidebarCompact = saved.0
            state.sidebarVisible = saved.1
            state.browserPreferences.showPinnedGrid = saved.3
            LayoutSwitch.set(tabs: saved.2 == true, state: state)
        }
        LayoutSwitch.set(tabs: false, state: state)
        state.browserPreferences.sidebarCompact = rail ? true : nil
        state.browserPreferences.showPinnedGrid = false
        state.sidebarVisible = true
        try? await Task.sleep(for: .milliseconds(800))

        /// Three groups at the top (Work open with two tabs, Home open with one, Read open with one, Inner inside
        /// Read), and four loose tabs; built again for each case.
        struct Fixture {
            var tabs: [TabItem]
            var work: TabFolder, home: TabFolder, read: TabFolder, inner: TabFolder
            var loose: [TabItem] { Array(tabs.suffix(4)) }
        }
        func build(shutWork: Bool = false) async -> Fixture {
            let tabs = (0..<9).compactMap { state.newTab(url: "about:blank#bug\($0)", select: false) }
            let work = state.createFolder(named: "Work"), home = state.createFolder(named: "Home"), read = state.createFolder(named: "Read")
            let inner = state.createFolder(named: "Inner", parentID: read.id)
            for (tab, folder) in zip(tabs, [work, work, home, read, inner]) { state.moveToFolder(tab.id, folderID: folder.id) }
            for folder in [work, home, read] { state.placeFolderInBlock(folder.id) }
            if shutWork, let index = state.folders.firstIndex(where: { $0.id == work.id }) { state.folders[index].isOpen = false }
            try? await Task.sleep(for: .milliseconds(400))
            return Fixture(tabs: tabs, work: work, home: home, read: read, inner: inner)
        }
        func clear(_ fixture: Fixture) async {
            for tab in fixture.tabs { state.closeTab(tab.id, removingPin: true) }
            for folder in [fixture.inner, fixture.work, fixture.home, fixture.read] { state.deleteFolder(folder.id) }
            try? await Task.sleep(for: .milliseconds(200))
        }
        guard let rig = OutlineDragRig(browser) else {
            check(false, "the sidebar list is on screen")
            print("IKTEST \(name)checks FAIL failures=\(failures)")
            return
        }
        rigForDetail = rig
        let tag = rail ? "rail-" : "sidebar-"
        func top() -> [String] { state.sidebarOutline.rows.map(\.id) }
        func sits(_ id: String, before next: String) -> Bool {
            let ids = top()
            return ids.firstIndex(of: id).map { $0 + 1 < ids.count && ids[$0 + 1] == next } ?? false
        }
        func below(_ id: String) -> NSPoint { rig.point(row: min(rig.outlineView.numberOfRows - 1, rig.row(id) + 3), fraction: 0.5) }
        func above(_ id: String) -> NSPoint { rig.point(row: max(0, rig.row(id) - 2), fraction: 0.5) }

        // 1. Just above a group: above it, not in it nor in the open group above (Work open, then shut).
        for shut in [false, true] {
            let way = shut ? " (the group above shut)" : " (the group above open)"
            var f = await build(shutWork: shut)
            let home = "group:" + f.home.id
            rig.shot("\(tag)1-tab-before\(shut ? "-shut" : "")")
            var took = await rig.drag(PretendDrag(tab: f.loose[1].id, window: rig.window), from: below(home), over: home, upper: true,
                                      shot: "\(tag)1-tab-during\(shut ? "-shut" : "")")
            _ = await rig.settle()
            rig.shot("\(tag)1-tab-after\(shut ? "-shut" : "")")
            for wait in [100, 250, 600] {
                try? await Task.sleep(for: .milliseconds(wait))
                rig.shot("\(tag)1-tab-after\(shut ? "-shut" : "")-\(wait)")
            }
            check(took && sits("tab:" + f.loose[1].id, before: home) && f.loose[1].folderID == nil,
                  "1: a tab dropped just above a group lands above it\(way)")
            await clear(f)

            f = await build(shutWork: shut)
            took = await rig.drag(PretendDrag(group: f.read.id, window: rig.window), from: below("group:" + f.read.id), over: "group:" + f.home.id, upper: true,
                                  shot: "\(tag)1-group-during\(shut ? "-shut" : "")")
            _ = await rig.settle()
            rig.shot("\(tag)1-group-after\(shut ? "-shut" : "")")
            check(took && sits("group:" + f.read.id, before: "group:" + f.home.id) && state.folders.first { $0.id == f.read.id }?.parentID == nil,
                  "1: a group dropped just above a group lands above it\(way)")
            await clear(f)

            f = await build(shutWork: shut)
            took = await rig.drag(PretendDrag(tab: f.loose[0].id, window: rig.window), from: above("group:" + f.read.id), over: "group:" + f.read.id, upper: true)
            _ = await rig.settle()
            check(took && sits("tab:" + f.loose[0].id, before: "group:" + f.read.id) && f.loose[0].folderID == nil,
                  "1: a tab dragged down to just above a group lands above it\(way)")
            await clear(f)
        }

        // 2. Out of a group: drawn as a loose row.
        var f = await build()
        let leaving = f.tabs[1]
        rig.shot("\(tag)2-before")
        var took = await rig.drag(PretendDrag(tab: leaving.id, window: rig.window), from: rig.point(over: "tab:" + leaving.id, upper: true),
                                  over: "tab:" + f.loose[1].id, upper: true, shot: "\(tag)2-during")
        _ = await rig.settle()
        try? await Task.sleep(for: .milliseconds(300))
        rig.shot("\(tag)2-after")
        let placed = rig.list.placeForCheck("tab:" + leaving.id)
        check(took && leaving.folderID == nil && placed?.leading == (rail ? 0 : SidebarOutlineList.margin) && placed?.card == nil, "2: a tab dragged out of a group among the tabs has no card or indent")
        took = await rig.drag(PretendDrag(tab: f.tabs[0].id, window: rig.window), from: rig.point(over: "tab:" + f.tabs[0].id, upper: true),
                              over: "group:" + f.home.id, upper: true)
        _ = await rig.settle()
        try? await Task.sleep(for: .milliseconds(300))
        rig.shot("\(tag)2-after-right-below")
        let pinnedOut = rig.list.placeForCheck("tab:" + f.tabs[0].id)
        check(took && f.tabs[0].folderID == nil && pinnedOut?.leading == (rail ? 0 : SidebarOutlineList.margin) && pinnedOut?.card == nil,
              "2: a tab dragged out to right below its group has no card or indent")
        await clear(f)

        // 3. In and out, over and over, nested groups too; the list follows every time.
        f = await build()
        var followed = true
        for round in 0..<30 {
            let tab = f.loose[round % 4]
            let groups = [f.work, f.home, f.read, f.inner]
            let group = groups[round % groups.count]
            let into = await rig.drag(PretendDrag(tab: tab.id, window: rig.window), from: rig.point(over: "tab:" + tab.id, upper: true),
                                      over: "group:" + group.id, upper: false)
            let inside = await rig.settle()
            followed = followed && inside.isEmpty && into && tab.folderID == group.id
            let next = top().last { $0.hasPrefix("tab:") && $0 != "tab:" + tab.id } ?? "divider"
            let out = await rig.drag(PretendDrag(tab: tab.id, window: rig.window), from: rig.point(over: "tab:" + tab.id, upper: true),
                                     over: next, upper: true)
            let outside = await rig.settle()
            followed = followed && outside.isEmpty && out && tab.folderID == nil
            if !followed {
                print("IKTEST \(name) detail round \(round): \(rig.summary())")
                break
            }
        }
        rig.shot("\(tag)3-after")
        check(followed, "3: tabs dragged into and out of groups 30 times land each time and the list follows")
        await clear(f)

        // 4. Between two groups at the top, and out again from there.
        f = await build()
        rig.shot("\(tag)4-before")
        took = await rig.drag(PretendDrag(tab: f.loose[2].id, window: rig.window), from: below("group:" + f.read.id), over: "group:" + f.read.id, upper: true,
                              shot: "\(tag)4-tab-during")
        _ = await rig.settle()
        check(took && sits("tab:" + f.loose[2].id, before: "group:" + f.read.id), "4: a tab dropped between two groups lands between them")
        took = await rig.drag(PretendDrag(group: f.work.id, window: rig.window), from: above("group:" + f.read.id), over: "group:" + f.read.id, upper: true,
                              shot: "\(tag)4-group-during")
        _ = await rig.settle()
        rig.shot("\(tag)4-between")
        check(took && sits("group:" + f.work.id, before: "group:" + f.read.id) && state.folders.first { $0.id == f.work.id }?.parentID == nil,
              "4: a group dropped between two groups lands between them")
        // Neither is last; both come out again.
        took = await rig.drag(PretendDrag(tab: f.loose[2].id, window: rig.window), from: rig.point(over: "tab:" + f.loose[2].id, upper: true),
                              over: "tab:" + f.loose[0].id, upper: true)
        _ = await rig.settle()
        check(took && !f.loose[2].pinned && sits("tab:" + f.loose[2].id, before: "tab:" + f.loose[0].id), "4: a tab between two groups drags out again")
        took = await rig.drag(PretendDrag(group: f.work.id, window: rig.window), from: rig.point(over: "group:" + f.work.id, upper: true),
                              over: "tab:" + f.loose[1].id, upper: true)
        _ = await rig.settle()
        rig.shot("\(tag)4-after")
        check(took && sits("group:" + f.work.id, before: "tab:" + f.loose[1].id), "4: a group between two groups drags out again")
        await clear(f)

        print("IKTEST \(name)checks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }
}
#endif
