#if DEBUG
import Foundation

/// The sidebar's rows (`SidebarOutline`) and its one drop rule, without the list: where a row dropped at each kind of
/// place lands, what it becomes there (a pinned row above the divider, a loose tab below it, a member inside a group),
/// and, over thousands of seeded random moves, that the rows read back from the tabs are exactly the outline the move
/// made.
@MainActor
enum OutlineChecks {
    static func run(_ browser: BrowserWindowController) {
        var failures = 0
        func check(_ value: Bool, _ title: String) {
            print("IKTEST outline \(value ? "PASS" : "FAIL") \(title)")
            if !value { failures += 1 }
        }
        let root = FileManager.default.temporaryDirectory.appending(path: "IkagoOutline-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let state = BrowserState(store: SessionStore(directory: root))
        state.browserPreferences.showPinnedGrid = false
        func tab(_ name: String) -> TabItem { state.newTab(url: "https://\(name).example", select: false)! }
        func ids(_ rows: [SidebarOutline.Row]) -> [String] { rows.map(\.id) }
        func outline() -> SidebarOutline { state.sidebarOutline }
        func rows(_ id: String) -> [SidebarOutline.Row] { [outline().row(id)!] }
        func group(_ name: String) -> TabFolder {
            let folder = state.createFolder(named: name)
            state.placeFolderInBlock(folder.id)
            return folder
        }

        // Block: a pin, group A (open, two tabs), group B (open, one tab), group C (shut, one tab). Loose: four tabs.
        let a1 = tab("a1"), a2 = tab("a2"), b1 = tab("b1"), c1 = tab("c1")
        let l1 = tab("l1"), l2 = tab("l2"), l3 = tab("l3"), l4 = tab("l4")
        let pin = tab("pin"); state.movePin(pin.id, intoGrid: false)
        let a = group("A"), b = group("B"), c = group("C")
        state.moveToFolder(a1.id, folderID: a.id); state.moveToFolder(a2.id, folderID: a.id)
        state.moveToFolder(b1.id, folderID: b.id); state.moveToFolder(c1.id, folderID: c.id)
        if let index = state.folders.firstIndex(where: { $0.id == c.id }) { state.folders[index].isOpen = false }
        let (ga, gb, gc) = ("group:" + a.id, "group:" + b.id, "group:" + c.id)
        func t(_ tab: TabItem) -> String { "tab:" + tab.id }

        check(ids(outline().rows) == [t(pin), ga, gb, gc, "divider", t(l1), t(l2), t(l3), t(l4)], "pins, the block's groups, the divider, then the tabs")
        check(outline().tabOrder == state.navigationOrder.map(\.id), "the list's tab order is next/previous tab's order")

        // The rule, case by case.
        let o = outline()
        check(o.place(for: rows(t(l3)), at: .before(gb)) == .init(parent: nil, index: 2), "the gap above a group is before it, not the end of the open group above (bug 1)")
        check(o.place(for: rows(ga), at: .before(gb)) == .init(parent: nil, index: 1), "a group dropped above the next group lands between them (bug 4)")
        check(o.place(for: rows(t(l3)), at: .into(a.id)) == .init(parent: a.id, index: 0), "onto an open group is first in it")
        check(o.place(for: rows(t(l3)), at: .into(c.id)) == .init(parent: c.id, index: 1), "onto a shut group is last in it")
        check(o.place(for: rows(t(l3)), at: .before(t(a1))) == .init(parent: a.id, index: 0), "the gap under an open group's header is first in it")
        check(o.place(for: rows(t(l3)), at: .before("divider")) == .init(parent: nil, index: 4), "above the divider is the end of the block")
        check(o.place(for: rows(t(l3)), at: .before(t(l1))) == .init(parent: nil, index: 5), "below the divider is the first loose tab")
        check(o.place(for: rows(t(l1)), at: .end) == .init(parent: nil, index: 8), "below every row is last")
        check(o.place(for: rows(t(l2)), at: .before(t(l2))) == .init(parent: nil, index: 6)
              && o.place(for: rows(t(l2)), at: .before(t(l3))) == .init(parent: nil, index: 6), "a row dropped next to itself stays")
        check(o.place(for: rows(ga), at: .before(t(a1))) == nil && o.place(for: rows(ga), at: .into(a.id)) == nil
              && o.place(for: rows(ga), at: .before(gb)) == .init(parent: nil, index: 1), "a group never goes inside itself, and next to itself it stays")

        // What rows become where they land.
        state.moveSidebarRows(rows(t(l4)), to: .before(t(b1)))
        check(state.tab(l4.id)?.folderID == b.id && state.tabs(in: b).map(\.id) == [l4.id, b1.id], "a tab dropped first in a group joins it there")
        state.moveSidebarRows(rows(t(l4)), to: .before(gc))
        check(l4.pinned && l4.pinAsRow && l4.pinAfterFolderID == b.id && ids(outline().rows).prefix(5) == [t(pin), ga, gb, t(l4), gc],
              "a tab dropped between two block groups becomes a pinned row between them")
        state.moveSidebarRows(rows(t(l4)), to: .before(gc))
        check(ids(outline().rows).prefix(5) == [t(pin), ga, gb, t(l4), gc], "and stays when dropped next to itself")
        state.moveSidebarRows(rows(t(l4)), to: .end)
        check(!l4.pinned && l4.folderID == nil && ids(outline().rows).last == t(l4), "a pinned row dropped among the tabs is a loose tab")
        state.moveSidebarRows(rows(gc), to: .before(t(l3)))
        check(state.folders.first { $0.id == c.id }?.afterTabID == l2.id && ids(outline().rows).firstIndex(of: gc) == ids(outline().rows).firstIndex(of: t(l2))! + 1,
              "a group dropped among the tabs sits after the tab above it")
        state.moveSidebarRows(rows(gc), to: .before(t(a1)))
        check(state.folders.first { $0.id == c.id }?.parentID == a.id && outline().rows(in: a.id).map(ids)?.first == gc, "a group dropped into a group nests, ahead of its tabs")
        state.moveSidebarRows(rows(t(l1)), to: .before(gc))
        check(outline().rows(in: a.id).map(ids) == [gc, t(l1), t(a1), t(a2)], "a tab dropped above a group's groups goes after them")
        state.moveSidebarRows(rows(gb), to: .before(t(a2)))
        check(outline().rows(in: a.id).map(ids) == [gc, gb, t(l1), t(a1), t(a2)], "a group dropped among a group's tabs goes after its groups")
        state.moveSidebarRows(rows(gb), to: .before(t(pin)))
        check(ids(outline().rows).first == gb && state.folders.first { $0.id == b.id }?.parentID == nil, "a group dropped above the first row is first")
        check(outline().tabOrder == state.navigationOrder.map(\.id), "after every move the orders still agree")

        // Pins placed after a group stay in the block when the group goes into another.
        let afterA = ids(outline().rows)[ids(outline().rows).firstIndex(of: ga)! + 1]
        state.moveSidebarRows(rows(t(l3)), to: .before(afterA))
        check(l3.pinned && l3.pinAfterFolderID == a.id, "a tab dropped right after a block group is a pin placed after it")
        state.moveSidebarRows(rows(ga), to: .into(b.id))
        check(l3.pinned && l3.pinAfterFolderID != a.id && ids(outline().rows).contains(t(l3)),
              "a pin after a group stays in the block when the group nests")

        // A tab dropped in from somewhere else (not a row yet), a split row moving as one.
        let outside = tab("outside")
        state.togglePin(outside.id)  // a pin in the grid would be out of the list; here pins are rows
        state.splitTabs(l1.id, with: l2.id)
        if let split = outline().row("split:" + (state.splitGroup(of: l1.id) ?? []).joined(separator: ",")) {
            state.moveSidebarRows([split], to: .into(b.id))
            check(state.tab(l1.id)?.folderID == b.id && state.tab(l2.id)?.folderID == b.id, "a split row moves as one")
        } else {
            check(false, "a split row moves as one")
        }

        // Seeded random moves: the rows read back are the outline the move made, and nothing is lost.
        var random = SplitMix(seed: 5)
        for index in 0..<6 { _ = tab("r\(index)") }
        for name in ["D", "E"] { let folder = group(name); state.moveToFolder(tab(name).id, folderID: folder.id) }
        var moves = 0, refused = 0, wrong = 0
        let allTabs = Set(state.spaceTabs.map(\.id))
        func tree(_ rows: [SidebarOutline.Row]) -> String {
            rows.map { $0.id + ($0.children.isEmpty ? "" : "[" + tree($0.children) + "]") }.joined(separator: " ")
        }
        for step in 0..<3000 {
            if step % 50 == 0, let id = state.spaceFolders.randomElement(using: &random)?.id { state.toggleFolder(id) }
            let now = outline()
            var everything: [SidebarOutline.Row] = []
            func collect(_ list: [SidebarOutline.Row]) { for row in list { everything.append(row); collect(row.children) } }
            collect(now.rows)
            let movable = everything.filter { $0.kind != .divider }
            guard let moving = movable.randomElement(using: &random) else { break }
            let anchor = everything.randomElement(using: &random)!
            let target: SidebarOutline.Target = switch random.next() % 5 {
            case 0, 1, 2: .before(anchor.id)
            case 3: anchor.groupID.map { .into($0) } ?? .before(anchor.id)
            default: .end
            }
            guard let place = now.place(for: [moving], at: target) else { refused += 1; continue }
            let expected = now.moving([moving], to: place)
            state.moveSidebarRows([moving], to: target)
            moves += 1
            if tree(outline().rows) != tree(expected.rows) {
                wrong += 1
                if wrong <= 3 { print("IKTEST outline detail step \(step) \(moving.id) at \(target): want \(tree(expected.rows)) got \(tree(outline().rows))") }
            }
        }
        check(wrong == 0, "\(moves) random moves read back as the outline they made (\(refused) refused)")
        check(Set(state.spaceTabs.map(\.id)) == allTabs && Set(outline().tabOrder) == allTabs.subtracting(state.sidebarGridPinnedTabs.map(\.id)),
              "every tab is still there and in the list")
        check(outline().tabOrder == state.navigationOrder.map(\.id), "and the list's order is still next/previous tab's")

        // Many tabs: the outline builds quickly.
        for i in 0..<1000 { _ = state.newTab(url: "https://many\(i).example", select: false) }
        let start = Date()
        let big = state.sidebarOutline
        let ms = Date().timeIntervalSince(start) * 1000
        check(big.tabOrder.count >= 1000 && ms < 50, "1,000 tabs build in \(Int(ms)) ms")
        print("IKTEST outlinechecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }
}
#endif
