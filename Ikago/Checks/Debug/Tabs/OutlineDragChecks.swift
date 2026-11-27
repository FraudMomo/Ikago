#if DEBUG
import AppKit

/// The sidebar list's drops, driven with a pretend drag (the real pointer is never moved): rows and groups land between
/// rows where dropped, at the top too, a closed group takes a row dropped onto it,
/// a move keeps every row's view (a new one draws empty for a moment), and a dropped row appears at its place at once
/// instead of sliding there from where it was.
@MainActor
enum OutlineDragChecks {
    /// `rail`: the icon sidebar's list (the same list, drawn as tiles).
    static func run(_ browser: BrowserWindowController, rail: Bool = false) async {
        var failures = 0
        let name = rail ? "raildrag" : "outlinedrag"
        func check(_ value: Bool, _ title: String) {
            print("IKTEST \(name) \(value ? "PASS" : "FAIL") \(title)")
            if !value { failures += 1 }
        }
        let state = browser.state
        let saved = (state.browserPreferences.sidebarCompact, state.sidebarVisible, state.browserPreferences.pinnedRowsStayInView,
                     state.browserPreferences.sidebarTopTabs)
        defer {
            state.browserPreferences.sidebarCompact = saved.0
            state.sidebarVisible = saved.1
            state.browserPreferences.pinnedRowsStayInView = saved.2
            LayoutSwitch.set(tabs: saved.3 == true, state: state)
        }
        // The full sidebar on its own list, or the icon sidebar.
        LayoutSwitch.set(tabs: false, state: state)
        state.browserPreferences.sidebarCompact = rail ? true : nil
        state.browserPreferences.pinnedRowsStayInView = nil
        state.sidebarVisible = true
        var made: [TabItem] = []
        for index in 0..<5 { if let tab = state.newTab(url: "about:blank#drag\(index)", select: false) { made.append(tab) } }
        let closed = state.createFolder(named: "Closed Drop")
        state.placeFolderAmongTabs(closed.id, relativeTo: made[4].id, after: true)
        if let index = state.folders.firstIndex(where: { $0.id == closed.id }) { state.folders[index].isOpen = false }
        try? await Task.sleep(for: .milliseconds(800))
        guard let rig = OutlineDragRig(browser) else {
            check(false, "the sidebar list is on screen")
            print("IKTEST \(name)checks FAIL failures=\(failures)")
            return
        }
        let (outlineView, window) = (rig.outlineView, rig.window)
        let (t0, t1, t2, t3) = (made[0], made[1], made[2], made[3])
        /// Each shown row's view, to see that a move keeps them (a new one draws empty for a moment).
        func views() -> [String: NSView] {
            var out: [String: NSView] = [:]
            for row in 0..<outlineView.numberOfRows {
                if let item = outlineView.item(atRow: row) as? OutlineNode, let view = outlineView.view(atColumn: 0, row: row, makeIfNecessary: false) {
                    out[item.id] = view
                }
            }
            return out
        }
        /// Whether the dropped row is sliding to its place from where it was: drawn more than a row away from it. (AppKit
        /// closes the drop's gap with its own short animation, which moves rows by less than a row.)
        func sliding(_ id: String) -> Bool {
            let row = rig.row(id)
            guard row >= 0, let layer = outlineView.rowView(atRow: row, makeIfNecessary: false)?.layer,
                  let shown = layer.presentation() else { return false }
            let far = abs(shown.frame.minY - layer.frame.minY) > outlineView.rowHeight + outlineView.intercellSpacing.height + 0.5
            if far { print("IKTEST \(name) detail \(id.suffix(4)) drawn at \(shown.frame.minY), its place \(layer.frame.minY), animations \(layer.animationKeys() ?? [])") }
            return far
        }

        let drag = PretendDrag(tab: t0.id, window: window)
        // Between rows: before the fourth tab. Every row keeps its view through the move.
        outlineView.scrollRowToVisible(rig.row("tab:" + t3.id))
        // The moved tab and the tabs around it (rows at the edge of the view may scroll out and get new views, as any list's).
        let near = Set([t0, t1, t2, t3].map { "tab:" + $0.id })
        let kept = views().filter { near.contains($0.key) }
        let moved = await rig.drop(drag, at: rig.point(over: "tab:" + t3.id, upper: true))
        let followed = await rig.settle()
        let ids = rig.rowIDs()
        check(moved && ids.firstIndex(of: "tab:" + t0.id).map { ids[$0 + 1] == "tab:" + t3.id } == true, "a tab dropped between rows lands there")
        let now = views()
        check(followed.isEmpty && kept.count == near.count && kept.allSatisfy { id, view in now[id].map { $0 === view } ?? true },
              "a move keeps every row's view (none redraws empty)")
        check(!sliding("tab:" + t0.id), "a row dropped down appears at its place at once")

        // The other way: a tab dropped up, above the tabs before it. It appears in the gap, not sliding up from where it was.
        let upFrom = rig.rowIDs().firstIndex(of: "tab:" + t3.id) ?? 0
        let up = await rig.drop(PretendDrag(tab: t3.id, window: window), at: rig.point(over: rig.rowIDs()[max(0, upFrom - 3)], upper: true))
        _ = await rig.settle()
        check(up && rig.rowIDs().firstIndex(of: "tab:" + t3.id).map { $0 < upFrom } == true, "a tab dropped up lands there")
        check(!sliding("tab:" + t3.id), "a row dropped up appears at its place at once")

        // To the top of the tabs (right under New Tab), and a group to the very top of the list.
        if let line = rig.rowIDs().firstIndex(of: "divider") {
            let top = await rig.drop(PretendDrag(tab: t3.id, window: window), at: rig.point(over: "divider", upper: false))
            _ = await rig.settle()
            check(top && rig.rowIDs()[line + 1] == "tab:" + t3.id, "a tab dropped at the top of the tabs goes there")
        }
        let groupTop = await rig.drop(PretendDrag(group: closed.id, window: window), at: rig.point(over: rig.rowIDs()[0], upper: true))
        _ = await rig.settle()
        check(groupTop && rig.rowIDs().first == "group:" + closed.id, "a group dropped at the top of the list goes there")

        // Onto a closed group: the tab goes in, last.
        let joined = await rig.drop(PretendDrag(tab: t1.id, window: window), at: rig.point(over: "group:" + closed.id, upper: false))
        _ = await rig.settle()
        check(joined && state.tab(t1.id)?.folderID == closed.id, "a tab dropped onto a closed group joins it")

        // The outline's own drag path takes a drop too.
        let native = await rig.dragAndDrop(PretendDrag(tab: t2.id, window: window), to: rig.point(row: rig.row("tab:" + t0.id), fraction: 0.2))
        _ = await rig.settle()
        check(native, "the outline's own drag and drop takes the row")

        // The selected tabs travel with the dragged one, together and in order, before the row they were dropped before
        // (here all of them sit above that row, which a place counted in rows would miss).
        let loose = rig.rowIDs().drop { $0 != "divider" }.dropFirst().filter { $0.hasPrefix("tab:") }
        if loose.count >= 4 {
            let (first, dragged, companion, next) = (loose[0], loose[1], loose[2], loose[3])
            TabDrag.companions = [String(companion.dropFirst(4))]
            let together = await rig.drop(PretendDrag(tab: String(dragged.dropFirst(4)), window: window), at: rig.point(over: next, upper: true))
            _ = await rig.settle()
            let order = rig.rowIDs()
            check(together && order.firstIndex(of: first).map { order[$0 + 1] == dragged && order[$0 + 2] == companion && order[$0 + 3] == next } == true,
                  "selected tabs dropped together land in order before the row they were dropped before")
        }

        state.deleteFolder(closed.id)
        for tab in made { state.closeTab(tab.id) }
        print("IKTEST \(name)checks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }
}
#endif
