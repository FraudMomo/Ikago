#if DEBUG
import Foundation

/// Groups inside groups: order, loop refusal, and deleting a middle group.
@MainActor
enum NestedGroupChecks {
    static func run(_ browser: BrowserWindowController) {
        let state = browser.state
        var failures = 0
        func check(_ value: Bool, _ title: String) {
            print("IKTEST nestedgroups \(value ? "PASS" : "FAIL") \(title)")
            if !value { failures += 1 }
        }
        let outer = state.createFolder(named: "Outer")
        let middle = state.createFolder(named: "Middle", parentID: outer.id)
        let inner = state.createFolder(named: "Inner", parentID: middle.id)
        let a = state.newTab(url: "about:blank#outer", select: false, folderID: outer.id)!
        let b = state.newTab(url: "about:blank#middle", select: false, folderID: middle.id)!
        let c = state.newTab(url: "about:blank#inner", select: false, folderID: inner.id)!
        let order = state.orderedSpaceFolders.map(\.id)
        check(order.firstIndex(of: outer.id)! < order.firstIndex(of: middle.id)! && order.firstIndex(of: middle.id)! < order.firstIndex(of: inner.id)!,
              "groups list depth first")
        check(!state.childFolders(of: nil).contains { $0.id == middle.id } && state.childFolders(of: middle.id).map(\.id) == [inner.id],
              "nested groups are not top level")
        check(Set(state.tabs(inSubtree: outer).map(\.id)) == [a.id, b.id, c.id], "subtree holds every nested tab")
        state.moveFolder(outer.id, into: inner.id)
        check(state.folders.first { $0.id == outer.id }?.parentID == nil, "a group can't move into its own group")
        check(!state.folderMoveTargets(for: outer.id).contains { [middle.id, inner.id].contains($0.id) }, "menu offers no loops")
        state.deleteFolder(middle.id)
        check(state.folders.first { $0.id == inner.id }?.parentID == outer.id && b.folderID == outer.id,
              "deleting a middle group moves its groups and tabs up")
        state.moveFolder(inner.id, into: nil)
        check(state.childFolders(of: nil).contains { $0.id == inner.id }, "moving out returns a group to the top level")
        // Dragging groups by their headers: before, after, inside, and to the end of the list.
        let x = state.createFolder(named: "X"), y = state.createFolder(named: "Y")
        func top() -> [String] { state.childFolders(of: nil).map(\.id) }
        state.placeFolder(y.id, relativeTo: outer.id, after: false)
        check(top().firstIndex(of: y.id)! + 1 == top().firstIndex(of: outer.id)!, "a group drops before another")
        state.placeFolder(y.id, relativeTo: x.id, after: true)
        check(top().firstIndex(of: x.id)! + 1 == top().firstIndex(of: y.id)!, "a group drops after another")
        state.moveFolder(x.id, into: outer.id)
        check(state.childFolders(of: outer.id).last?.id == x.id, "a group dropped inside goes last among its groups")
        state.placeFolder(y.id, relativeTo: x.id, after: false)
        check(state.folders.first { $0.id == y.id }?.parentID == outer.id
              && state.childFolders(of: outer.id).map(\.id).suffix(2) == [y.id, x.id], "placing beside a nested group nests it there")
        check(!state.canPlaceFolder(outer.id, relativeTo: y.id) && !state.canPlaceFolder(outer.id, relativeTo: outer.id),
              "a group can't be dropped into or beside its own groups")
        state.placeFolder(outer.id, relativeTo: y.id, after: false)
        check(state.folders.first { $0.id == outer.id }?.parentID == nil, "a refused drop changes nothing")
        state.moveFolder(y.id, into: nil)
        check(top().last == y.id && state.folders.first { $0.id == y.id }?.parentID == nil, "the list's end takes a group to the top level, last")
        for id in [x.id, y.id] { state.deleteFolder(id) }
        for id in [a.id, b.id, c.id] { state.closeTab(id) }
        for id in [outer.id, inner.id] { state.deleteFolder(id) }
        print("IKTEST nestedgroupchecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }
}
#endif
