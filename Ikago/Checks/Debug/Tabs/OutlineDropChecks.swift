#if DEBUG
import AppKit

/// Where the list takes a drop, through the outline's own drag path (a pretend drag moved in small steps to the pointer's
/// place, the gap opening as it goes; the real pointer is never moved): the upper part of a group's header is the place
/// above the group, so a row can go above the first group, and its lower part is into the group (first when it is open).
@MainActor
enum OutlineDropChecks {
    /// `rail`: the icon sidebar's list (the same list, drawn as tiles).
    static func run(_ browser: BrowserWindowController, rail: Bool = false) async {
        var failures = 0
        let name = rail ? "raildrop" : "outlinedrop"
        func check(_ value: Bool, _ title: String) {
            print("IKTEST \(name) \(value ? "PASS" : "FAIL") \(title)")
            if !value {
                failures += 1
                if let rig = rigForDetail { print("IKTEST \(name) rows now: \(rig.summary())") }
            }
        }
        let state = browser.state
        var rigForDetail: OutlineDragRig?
        let saved = (state.browserPreferences.sidebarCompact, state.sidebarVisible, state.browserPreferences.pinnedRowsStayInView,
                     state.browserPreferences.sidebarTopTabs, state.browserPreferences.showPinnedGrid)
        defer {
            state.browserPreferences.sidebarCompact = saved.0
            state.sidebarVisible = saved.1
            state.browserPreferences.pinnedRowsStayInView = saved.2
            state.browserPreferences.showPinnedGrid = saved.4
            LayoutSwitch.set(tabs: saved.3 == true, state: state)
        }
        LayoutSwitch.set(tabs: false, state: state)
        state.browserPreferences.sidebarCompact = rail ? true : nil
        state.browserPreferences.pinnedRowsStayInView = nil
        state.browserPreferences.showPinnedGrid = false
        state.sidebarVisible = true
        try? await Task.sleep(for: .milliseconds(800))

        /// Two block groups (the first open with two tabs, the second shut with one), a pinned tab, three loose tabs and a
        /// group among them, all built again for each drop.
        struct Fixture { var tabs: [TabItem]; var first: TabFolder; var second: TabFolder; var loose: TabFolder; var pin: TabItem }
        func build(pinned: Bool) async -> Fixture {
            let tabs = (0..<7).compactMap { state.newTab(url: "about:blank#drop\($0)", select: false) }
            let first = state.createFolder(named: "First")
            let second = state.createFolder(named: "Second")
            let loose = state.createFolder(named: "Loose")
            state.moveToFolder(tabs[0].id, folderID: first.id)
            state.moveToFolder(tabs[1].id, folderID: first.id)
            state.moveToFolder(tabs[2].id, folderID: second.id)
            state.placeFolderInBlock(first.id)
            state.placeFolderInBlock(second.id)
            state.placeFolderAmongTabs(loose.id, relativeTo: tabs[5].id, after: true)
            if let index = state.folders.firstIndex(where: { $0.id == second.id }) { state.folders[index].isOpen = false }
            if pinned { state.movePin(tabs[6].id, intoGrid: false) }
            try? await Task.sleep(for: .milliseconds(500))
            return Fixture(tabs: tabs, first: first, second: second, loose: loose, pin: tabs[6])
        }
        func clear(_ fixture: Fixture) {
            for tab in fixture.tabs { state.closeTab(tab.id, removingPin: true) }
            for folder in [fixture.first, fixture.second, fixture.loose] { state.deleteFolder(folder.id) }
        }
        guard let rig = OutlineDragRig(browser) else {
            check(false, "the sidebar list is on screen")
            print("IKTEST \(name)checks FAIL failures=\(failures)")
            return
        }
        rigForDetail = rig
        /// Drags a pretend drag to the pointer's place on a row (a fraction of the way down it) and drops it, as a hand
        /// would: in small steps from a few rows below it, or from inside the row itself. The place is where the row is
        /// before the drag opens its gap; the list's own proposals decide where the drop lands.
        func dragOver(_ rowID: String, fraction: CGFloat, fromBelow: Bool, _ drag: PretendDrag) async -> Bool {
            let target = rig.row(rowID)
            let end = rig.point(row: target, fraction: fraction)
            let begin = rig.point(row: fromBelow ? min(rig.outlineView.numberOfRows - 1, target + 3) : target, fraction: 0.5)
            _ = await rig.fromRunLoop { rig.outlineView.draggingEntered(drag) }
            for step in 0...12 {
                let t = CGFloat(step) / 12
                drag.location = NSPoint(x: begin.x + (end.x - begin.x) * t, y: begin.y + (end.y - begin.y) * t)
                _ = await rig.fromRunLoop { rig.outlineView.draggingUpdated(drag) }
            }
            let took = await rig.fromRunLoop { rig.drop(drag) }
            _ = await rig.settle()
            return took
        }
        /// The rows now: whether `id` is the row right before `next`, and its place (the list's first, or after a pinned row).
        func sits(_ id: String, before next: String) -> Bool {
            let ids = rig.rowIDs()
            return ids.firstIndex(of: id).map { $0 + 1 < ids.count && ids[$0 + 1] == next } ?? false
        }

        for pinned in [false, true] {
            let tag = pinned ? " (a pinned row above)" : ""
            for fromBelow in [true, false] {
                let way = fromBelow ? "from below" : "from the row"
                // Above the first group (below the pinned row, if there is one).
                var fixture = await build(pinned: pinned)
                var first = "group:" + fixture.first.id
                var took = await dragOver(first, fraction: 0.15, fromBelow: fromBelow, PretendDrag(group: fixture.loose.id, window: rig.window))
                check(took && sits("group:" + fixture.loose.id, before: first) && rig.rowIDs().firstIndex(of: first) == (pinned ? 2 : 1),
                      "a group over the top of the first group goes above it\(tag), \(way)")
                clear(fixture)

                fixture = await build(pinned: pinned)
                first = "group:" + fixture.first.id
                took = await dragOver(first, fraction: 0.15, fromBelow: fromBelow, PretendDrag(tab: fixture.tabs[4].id, window: rig.window))
                check(took && sits("tab:" + fixture.tabs[4].id, before: first) && fixture.tabs[4].pinned, "a tab over the top of the first group goes above it\(tag), \(way)")
                clear(fixture)

                // The very top of the list.
                if pinned {
                    fixture = await build(pinned: pinned)
                    took = await dragOver("tab:" + fixture.pin.id, fraction: 0.15, fromBelow: fromBelow, PretendDrag(group: fixture.loose.id, window: rig.window))
                    check(took && rig.rowIDs().first == "group:" + fixture.loose.id, "a group over the top of the first row goes first\(tag), \(way)")
                    clear(fixture)

                    fixture = await build(pinned: pinned)
                    took = await dragOver("tab:" + fixture.pin.id, fraction: 0.15, fromBelow: fromBelow, PretendDrag(tab: fixture.tabs[4].id, window: rig.window))
                    check(took && rig.rowIDs().first == "tab:" + fixture.tabs[4].id, "a tab over the top of the first row goes first\(tag), \(way)")
                    clear(fixture)
                }
                guard fromBelow else { continue }

                // Between groups, and into them.
                fixture = await build(pinned: pinned)
                took = await dragOver("group:" + fixture.second.id, fraction: 0.15, fromBelow: true, PretendDrag(group: fixture.loose.id, window: rig.window))
                check(took && sits("group:" + fixture.loose.id, before: "group:" + fixture.second.id), "a group over the top of a group goes between it and the one above\(tag)")
                clear(fixture)

                fixture = await build(pinned: pinned)
                took = await dragOver("group:" + fixture.second.id, fraction: 0.8, fromBelow: true, PretendDrag(tab: fixture.tabs[4].id, window: rig.window))
                check(took && fixture.tabs[4].folderID == fixture.second.id, "a tab over the lower part of a shut group joins it\(tag)")
                clear(fixture)

                fixture = await build(pinned: pinned)
                took = await dragOver("group:" + fixture.second.id, fraction: 0.8, fromBelow: true, PretendDrag(group: fixture.loose.id, window: rig.window))
                check(took && state.folders.first { $0.id == fixture.loose.id }?.parentID == fixture.second.id, "a group over the lower part of a group nests in it\(tag)")
                clear(fixture)

                fixture = await build(pinned: pinned)
                took = await dragOver("group:" + fixture.first.id, fraction: 0.8, fromBelow: true, PretendDrag(tab: fixture.tabs[4].id, window: rig.window))
                check(took && state.tabs(in: fixture.first).first?.id == fixture.tabs[4].id, "a tab over the lower part of an open group goes first in it\(tag)")
                clear(fixture)
            }
        }
        print("IKTEST \(name)checks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }
}
#endif
