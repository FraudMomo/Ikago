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
        for id in [a.id, b.id, c.id] { state.closeTab(id) }
        for id in [outer.id, inner.id] { state.deleteFolder(id) }
        print("IKTEST nestedgroupchecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }
}
#endif
