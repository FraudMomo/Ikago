#if DEBUG
import AppKit

/// The sidebar list under a long seeded run of drags (the real pointer is never moved): tabs and groups dropped with
/// the pointer anywhere over the list, half of them through the outline's own drag path (the gap opening as the pointer
/// moves in steps), mixed with groups opening and shutting, tabs coming and going and groups ungrouped. After every
/// drop the model must hold exactly the rows the one drop rule says, and after every step the outline (its rows on
/// screen, each group's rows, depths, parents) must equal the model's. A wrong move makes `NSOutlineView` raise and the
/// app stop, so a run that doesn't print its result is a failure. `IKAGO_STRESS_VERBOSE=1` prints every step;
/// `IKAGO_STRESS_STEPS`, `IKAGO_STRESS_SEED` and `IKAGO_STRESS_PAUSE_MS` (after each step) change the run.
@MainActor
enum OutlineStressChecks {
    /// `rail`: the icon sidebar's list, which leaves the pinned rows out.
    static func run(_ browser: BrowserWindowController, rail: Bool) async {
        let name = rail ? "railstress" : "outlinestress"
        let environment = ProcessInfo.processInfo.environment
        let verbose = environment["IKAGO_STRESS_VERBOSE"] != nil
        let steps = environment["IKAGO_STRESS_STEPS"].flatMap(Int.init) ?? 500
        let pause = environment["IKAGO_STRESS_PAUSE_MS"].flatMap(Int.init) ?? 0
        let state = browser.state
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
        // The icon sidebar shows pinned tabs as Essentials, so it leaves the pinned rows out of its list.
        state.browserPreferences.showPinnedGrid = rail
        state.sidebarVisible = true

        /// Ten tabs, groups A, B and C with groups inside A and B (A1, A2, B1), eight tabs spread over them, two pinned
        /// rows.
        var made: [TabItem] = []
        var outer: [TabFolder] = [], inner: [TabFolder] = []
        func addTab(in folder: String? = nil) {
            if let tab = state.newTab(url: "about:blank#stress\(made.count)", select: false, folderID: folder) { made.append(tab) }
        }
        func build() async {
            for _ in 0..<10 { addTab() }
            outer = [state.createFolder(named: "A"), state.createFolder(named: "B"), state.createFolder(named: "C")]
            inner = [state.createFolder(named: "A1", parentID: outer[0].id), state.createFolder(named: "A2", parentID: outer[0].id),
                     state.createFolder(named: "B1", parentID: outer[1].id)]
            for (index, tab) in made.prefix(8).enumerated() {
                state.moveToFolder(tab.id, folderID: (outer + inner)[index % 6].id)
            }
            outer.forEach { state.placeFolderInBlock($0.id) }
            state.placeFolderAmongTabs(outer[2].id, relativeTo: made[9].id, after: true)
            state.movePin(made[8].id, intoGrid: false)
            state.movePin(made[9].id, intoGrid: false)
            try? await Task.sleep(for: .milliseconds(600))
        }
        func teardown() {
            for tab in made { state.closeTab(tab.id, removingPin: true) }
            for folder in outer + inner { state.deleteFolder(folder.id) }
            made = []
        }
        await build()
        guard let rig = OutlineDragRig(browser) else {
            print("IKTEST \(name) FAIL the sidebar list is on screen")
            return
        }
        var random = SplitMix(seed: environment["IKAGO_STRESS_SEED"].flatMap(UInt64.init) ?? (rail ? 7 : 11))
        var stats: [String: Int] = [:]
        var failures = 0
        func fail(_ step: Int, _ what: String, _ problems: [String]) {
            failures += 1
            print("IKTEST \(name) FAIL step \(step) \(what): \(problems.first ?? "")")
        }
        let initial = await rig.settle()
        if !initial.isEmpty { fail(0, "at the start", initial) }

        /// Drops `drag` with the pointer at `point` and checks it landed where the rule says. `native`: through the
        /// outline's own drag path, from `start`, in steps (the gap opens and moves rows as it goes); the place is read
        /// from what is on screen when the drop is taken.
        func drop(_ drag: PretendDrag, at point: NSPoint, native: Bool, from start: NSPoint, label: String, step: Int) async {
            let moving = rig.moving(drag)
            var expected: SidebarOutline?
            var took = false
            if native {
                drag.location = start
                var operation = await rig.fromRunLoop { rig.outlineView.draggingEntered(drag) }
                for index in 1...6 {
                    let t = CGFloat(index) / 6
                    drag.location = NSPoint(x: start.x + (point.x - start.x) * t, y: start.y + (point.y - start.y) * t)
                    operation = await rig.fromRunLoop { rig.outlineView.draggingUpdated(drag) }
                }
                let rule = rig.expectedTarget(at: point)
                if let shown = rig.list.shownDropForCheck, shown != rule {
                    fail(step, label, ["the gap shows \(shown), the pointer is over \(rule)"])
                }
                expected = rig.expectedOutline(moving, at: rule)
                if operation == [] {
                    // A drop the list refuses ends as AppKit ends it: the drag leaves.
                    await rig.fromRunLoop { rig.outlineView.draggingExited(drag) }
                } else {
                    took = await rig.fromRunLoop { rig.drop(drag) }
                }
            } else {
                expected = rig.expectedOutline(moving, at: rig.expectedTarget(at: point))
                took = await rig.drop(drag, at: point)
            }
            stats[took ? (native ? "drags" : "drops") : "refused", default: 0] += 1
            if took != (expected != nil) {
                let local = rig.outlineView.convert(point, from: nil)
                fail(step, label, [(took ? "the list took a drop the rule refuses" : "the list refused a drop the rule allows") + " (pointer at \(Int(local.y)) of \(Int(rig.outlineView.frame.height)), shown \(String(describing: rig.list.shownDropForCheck)))"])
            } else if let expected, rig.tree(state.sidebarOutline) != rig.tree(expected) {
                fail(step, label, ["landed as \(rig.tree(state.sidebarOutline)), the rule says \(rig.tree(expected))"])
            }
        }
        /// Anywhere over the part of the list on screen (scrolled to a random place first), where a real pointer can be.
        func pointer() -> NSPoint {
            let rows = rig.outlineView.numberOfRows
            if rows > 0 { rig.outlineView.scrollRowToVisible(Int(random.next() % UInt64(rows))) }
            let visible = rig.outlineView.visibleRect
            let y = visible.minY + CGFloat(random.next() % UInt64(max(1, Int(visible.height))))
            return rig.outlineView.convert(NSPoint(x: visible.midX, y: y), to: nil)
        }
        func openAll() {
            for folder in outer + inner where !state.folders.contains(where: { $0.id == folder.id && $0.isOpen }) { state.toggleFolder(folder.id) }
        }

        // Named cases first, each on a fresh set: rows leaving or entering open groups in ways that left an outline's
        // own idea of its rows different from the model's.
        func scenario(_ title: String, _ change: () async -> Void) async {
            await change()
            let found = await rig.settle()
            if found.isEmpty { print("IKTEST \(name) PASS \(title)") } else { fail(0, title, found) }
            teardown(); await build()
        }
        func dropGroup(_ folder: TabFolder, into target: TabFolder) async {
            _ = await rig.drop(PretendDrag(group: folder.id, window: rig.window), at: rig.point(over: "group:" + target.id, upper: false))
        }
        func dropGroupFirst(_ folder: TabFolder) async {
            _ = await rig.drop(PretendDrag(group: folder.id, window: rig.window), at: rig.point(over: rig.rowIDs()[0], upper: true))
        }
        await scenario("an open group dragged onto a shut group, its rows and groups going with it") {
            openAll(); _ = await rig.settle()
            state.toggleFolder(outer[2].id); _ = await rig.settle()
            await dropGroup(outer[0], into: outer[2])
        }
        await scenario("an open group ungrouped, its rows and groups moving up") {
            openAll(); _ = await rig.settle()
            state.deleteFolder(outer[0].id)
        }
        await scenario("every tab of an open group closed") {
            openAll(); _ = await rig.settle()
            for tab in state.tabs(inSubtree: outer[0]) { state.closeTab(tab.id) }
        }
        await scenario("a group inside a group, the two then swapping places") {
            openAll(); _ = await rig.settle()
            await dropGroupFirst(inner[2]); _ = await rig.settle()
            await dropGroup(outer[1], into: inner[2])
        }
        await scenario("a shut group opened while a row leaves it, in one change") {
            openAll(); _ = await rig.settle()
            state.toggleFolder(outer[0].id); _ = await rig.settle()
            if let tab = state.tabs(in: outer[0]).first {
                state.toggleFolder(outer[0].id)
                state.moveToFolder(tab.id, folderID: nil)
            }
        }
        await scenario("a row moved out of a shut group, then the group opened") {
            openAll(); _ = await rig.settle()
            state.toggleFolder(outer[1].id); _ = await rig.settle()
            if let tab = state.tabs(in: outer[1]).first { state.moveToFolder(tab.id, folderID: nil) }
            _ = await rig.settle()
            state.toggleFolder(outer[1].id)
        }
        await scenario("an empty group dragged into a nested group, groups beside it shut, then a drag") {
            openAll(); _ = await rig.settle()
            let empty = state.createFolder(named: "Empty")
            state.placeFolderAmongTabs(empty.id, relativeTo: made.last?.id, after: true)
            _ = await rig.settle()
            let nested = inner[1]
            if verbose { print("IKSTRESS scenario before: \(rig.tree(state.sidebarOutline))") }
            _ = await rig.drag(PretendDrag(group: empty.id, window: rig.window), from: rig.point(over: "group:" + empty.id, upper: true),
                               over: "group:" + nested.id, upper: false)
            _ = await rig.settle()
            if verbose { print("IKSTRESS scenario moved: \(rig.tree(state.sidebarOutline))") }
            state.toggleFolder(inner[0].id); _ = await rig.settle()
            state.toggleFolder(empty.id); _ = await rig.settle()
            if verbose { print("IKSTRESS scenario toggled, dragging") }
            if let last = made.last {
                _ = await rig.drag(PretendDrag(tab: last.id, window: rig.window), from: rig.point(over: "tab:" + last.id, upper: true),
                                   over: "group:" + outer[0].id, upper: true)
            }
            state.deleteFolder(empty.id)
        }
        await scenario("a group moved into another and out again at once, and groups opened and shut meanwhile") {
            openAll(); _ = await rig.settle()
            await dropGroup(outer[1], into: outer[0])
            state.toggleFolder(outer[0].id)
            await dropGroupFirst(outer[1])
            state.toggleFolder(outer[0].id)
        }

        for step in 1...steps {
            var tabRows: [SidebarOutline.Row] = [], groupRows: [SidebarOutline.Row] = []
            func collect(_ list: [SidebarOutline.Row]) {
                for row in list {
                    if case .tabs = row.kind { tabRows.append(row) }
                    if row.groupID != nil { groupRows.append(row) }
                    collect(row.children)
                }
            }
            collect(rig.list.outline.rows)
            let choice = Int(random.next() % 100)
            var label: String
            switch choice {
            case 0..<75:
                let group = choice >= 50 && !groupRows.isEmpty
                guard let moving = group ? groupRows.randomElement(using: &random) : tabRows.randomElement(using: &random) else { continue }
                let drag = group ? PretendDrag(group: moving.groupID, window: rig.window) : PretendDrag(tab: moving.tabIDs.first, window: rig.window)
                let native = choice % 2 == 0
                label = "\(native ? "drag" : "drop") \(moving.id.suffix(4))"
                if verbose {
                    func open(_ rows: [SidebarOutline.Row]) -> String {
                        rows.map { $0.id.suffix(4) + ($0.groupID == nil ? "" : ($0.isOpen ? "+" : "-") + "[" + open($0.children) + "]") }.joined(separator: " ")
                    }
                    print("IKSTRESS \(step) \(label) before: \(open(state.sidebarOutline.rows))")
                }
                await drop(drag, at: pointer(), native: native, from: pointer(), label: label, step: step)
            case 75..<85:
                guard let id = groupRows.randomElement(using: &random)?.groupID else { continue }
                label = "toggle \(id.suffix(4))"
                if verbose { print("IKSTRESS \(step) \(label)") }
                state.toggleFolder(id)
                stats["toggles", default: 0] += 1
            case 85..<93:
                label = "add a tab"
                if verbose { print("IKSTRESS \(step) \(label)") }
                if made.count < 24 { addTab(in: groupRows.randomElement(using: &random)?.groupID) }
                stats["new tabs", default: 0] += 1
            case 93..<98:
                guard made.count > 8, let tab = tabRows.randomElement(using: &random)?.tabIDs.first, made.contains(where: { $0.id == tab }) else { continue }
                label = "close \(tab.suffix(4))"
                if verbose { print("IKSTRESS \(step) \(label)") }
                state.closeTab(tab)
                made.removeAll { $0.id == tab }
                stats["closed tabs", default: 0] += 1
            default:
                guard groupRows.count > 4, let id = groupRows.randomElement(using: &random)?.groupID else { continue }
                label = "ungroup \(id.suffix(4))"
                if verbose { print("IKSTRESS \(step) \(label)") }
                state.deleteFolder(id)
                stats["ungrouped", default: 0] += 1
            }
            let found = await rig.settle()
            if !found.isEmpty { fail(step, label, found) }
            if pause > 0 { try? await Task.sleep(for: .milliseconds(pause)) }
            if failures > 5 { break }
        }
        print("IKTEST \(name) steps=\(steps) \(stats.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))")
        teardown()
        print("IKTEST \(name)checks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }
}
#endif
