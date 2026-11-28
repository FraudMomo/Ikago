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
        // Delete Group closes the tabs of the group and the groups inside it (one tab: no question); Ungroup kept them.
        let doomed = state.createFolder(named: "Doomed"), doomedInner = state.createFolder(named: "Doomed inner", parentID: doomed.id)
        let doomedTab = state.newTab(url: "about:blank#doomed", select: false, folderID: doomedInner.id)!
        browser.deleteGroup(doomed.id)
        check(!state.folders.contains { [doomed.id, doomedInner.id].contains($0.id) } && state.tab(doomedTab.id) == nil,
              "deleting a group closes its tabs and nested groups")
        // Above the New Tab line a group is pinned: its tabs (and its groups' tabs) stay when closed; among the loose tabs
        // they close. Deleting the group closes them for good.
        let pinned = state.createFolder(named: "Pinned"), pinnedInner = state.createFolder(named: "Pinned inner", parentID: pinned.id)
        state.placeFolderInBlock(pinned.id)
        let pinnedTab = state.newTab(url: "about:blank#pinned", select: false, folderID: pinnedInner.id)!
        browser.closeTab(pinnedTab.id)
        check(state.usesTabsLayout || state.tab(pinnedTab.id)?.isHibernating == true, "closing a tab in a group above the line keeps it, unloaded")
        state.placeFolderAmongTabs(pinned.id, relativeTo: nil, after: false)
        let looseTab = state.newTab(url: "about:blank#loosegroup", select: false, folderID: pinned.id)!
        browser.closeTab(looseTab.id)
        check(state.tab(looseTab.id) == nil, "closing a tab in a group among the loose tabs closes it")
        state.placeFolderInBlock(pinned.id)
        browser.deleteGroup(pinned.id)
        check(state.tab(pinnedTab.id) == nil && !state.folders.contains { $0.id == pinned.id }, "deleting a group above the line closes its tabs for good")
        // Hiding a group takes it out of every list; the Tab Groups button appears to bring it back.
        let hiddenGroup = state.createFolder(named: "Hidden")
        let hiddenTab = state.newTab(url: "about:blank#hidden", select: false, folderID: hiddenGroup.id)!
        browser.hideGroup(hiddenGroup.id)
        check(!state.listedFolders.contains { $0.id == hiddenGroup.id } && !state.navigationOrder.contains { $0.id == hiddenTab.id }
              && state.addsTabGroupsButton(in: .sidebarBottom), "a hidden group leaves the lists and the Tab Groups button shows")
        state.reopenFolder(hiddenGroup.id, selecting: false)
        check(state.listedFolders.contains { $0.id == hiddenGroup.id } && !state.addsTabGroupsButton(in: .sidebarBottom)
              && state.folders.first { $0.id == hiddenGroup.id }?.isOpen == false, "shown again, it is back in the list, collapsed")
        state.closeTab(hiddenTab.id); state.deleteFolder(hiddenGroup.id)
        // Groups among tabs: placed after a loose tab, kept in place when that tab goes, back to the block on request.
        let la = state.newTab(url: "about:blank#la", select: false)!, lb = state.newTab(url: "about:blank#lb", select: false)!
        let lc = state.newTab(url: "about:blank#lc", select: false)!
        let among = state.createFolder(named: "Among")
        let inside = state.newTab(url: "about:blank#among", select: false, folderID: among.id)!
        state.placeFolderAmongTabs(among.id, relativeTo: lb.id, after: true)
        func looseOrder() -> [String] { state.looseEntries.compactMap { entry in
            switch entry { case .tab(let t): [la.id, lb.id, lc.id].contains(t.id) ? t.id : nil; case .folder(let f): f.id == among.id ? f.id : nil } } }
        check(looseOrder() == [la.id, lb.id, among.id, lc.id] && !state.blockFolders.contains { $0.id == among.id },
              "a group placed after a tab sits there among the tabs")
        let nav = state.navigationOrder.map(\.id)
        check((nav.firstIndex(of: lb.id) ?? 0) < (nav.firstIndex(of: inside.id) ?? 0) && (nav.firstIndex(of: inside.id) ?? 0) < (nav.firstIndex(of: lc.id) ?? 0),
              "next/previous tab follows the group where it sits")
        state.closeTab(lb.id)
        check(looseOrder() == [la.id, among.id, lc.id], "closing the tab before it keeps the group in its place")
        _ = state.reorderTab(lc.id, relativeTo: la.id, after: true)
        check(looseOrder() == [la.id, lc.id, among.id], "a tab dropped after the tab before a group goes above the group")
        state.placeFolderInBlock(among.id)
        check(state.blockFolders.contains { $0.id == among.id } && !looseOrder().contains(among.id), "a group goes back to the block")
        let made = state.createFolder(named: "From tab", with: lc.id)
        check(made.afterTabID == la.id || state.folders.first { $0.id == made.id }?.afterTabID == la.id,
              "a group made from a loose tab takes that tab's place")
        for tab in [la, lc, inside] { state.closeTab(tab.id) }
        for id in [among.id, made.id] { state.deleteFolder(id) }
        // A tab dropped on another's middle: a group of the two where the target was, or the two side by side.
        let ta = state.newTab(url: "about:blank#ta", select: false)!, tb = state.newTab(url: "about:blank#tb", select: false)!
        let tc = state.newTab(url: "about:blank#tc", select: false)!
        state.drop(tb.id, onto: ta, makeGroup: true)
        check(ta.folderID != nil && ta.folderID == tb.folderID, "dropping a tab on a tab's group half groups the two")
        state.splitTabs(tc.id, with: ta.id)
        check(state.splitGroup(of: ta.id)?.contains(tc.id) == true && state.activeTabID == tc.id,
              "dropping a tab on a tab's split half shows the two side by side")
        state.unsplitGroup(containing: ta.id)
        let pairFolder = ta.folderID
        for tab in [ta, tb, tc] { state.closeTab(tab.id) }
        if let pairFolder { state.deleteFolder(pairFolder) }
        // The command bar on actions (⇧⌘K), with nothing typed.
        browser.showCommandBar()
        check(browser.chrome.showPalette && browser.palette.scope == .actions && browser.palette.query.isEmpty
              && !browser.palette.suggestions.isEmpty, "the command bar opens on actions")
        browser.dismissCommandPalette()
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
