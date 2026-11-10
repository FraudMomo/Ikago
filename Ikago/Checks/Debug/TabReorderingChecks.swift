#if DEBUG
import AppKit

@MainActor
enum TabReorderingChecks {
    static func run(_ browser: BrowserWindowController) async {
        let state = browser.state, original = state.snapshot()
        var failures = 0
        func check(_ value: Bool, _ title: String) {
            print("IKTEST tabreordering \(value ? "PASS" : "FAIL") \(title)")
            if !value { failures += 1 }
        }
        defer { browser.chrome.endTabDrag(); state.apply(original) }
        browser.dismissCommandPalette()
        state.tabs = []; state.splits = []; state.folders = []
        let a = state.newTab(url: InternalPage.history.url)!
        let b = state.newTab(url: InternalPage.bookmarks.url)!
        let c = state.newTab(url: InternalPage.downloads.url)!
        let active = state.activeTabID
        state.reorderTab(a.id, relativeTo: c.id, after: true)
        check(state.looseTabs.map(\.id) == [b.id, c.id, a.id], "downward drop can insert after the last tab")
        state.reorderTab(a.id, relativeTo: b.id, after: false)
        check(state.looseTabs.map(\.id) == [a.id, b.id, c.id], "upward drop inserts before the target")
        state.reorderTab(a.id, relativeTo: b.id, after: true)
        check(state.looseTabs.map(\.id) == [b.id, a.id, c.id] && state.folders.isEmpty, "middle-of-row drop reorders without accidentally creating a group")
        check(state.activeTabID == active, "reordering does not switch the active tab")
        let folder = state.createFolder(named: "Work", with: b.id)
        state.reorderTab(a.id, relativeTo: b.id, after: true)
        check(state.tabs(in: folder).map(\.id) == [b.id, a.id], "insertion inherits the target's folder")
        state.moveTabToListEnd(a.id)
        check(a.folderID == nil && state.looseTabs.last?.id == a.id, "end-of-list drop exits a folder")
        state.moveToFolder(b.id, folderID: nil)
        state.splits = [[a.id, c.id]]
        state.reorderTab(a.id, relativeTo: b.id, after: false)
        check(state.looseTabs.map(\.id) == [a.id, c.id, b.id] && state.splits == [[a.id, c.id]], "split group moves as one item and keeps its layout")
        check(!state.reorderTab(a.id, relativeTo: c.id, after: true), "drop onto the same split group is rejected")
        state.splits = []
        let space = state.activeSpaceID
        _ = state.createSpace(name: "Other", symbol: "circle", isolated: true)
        let foreign = state.newTab(url: InternalPage.settings.url)!
        state.switchSpace(space)
        check(!state.reorderTab(foreign.id, relativeTo: b.id, after: false), "reorder cannot pull a tab from another Space")
        let foreignIndex = state.tabs.firstIndex { $0.id == foreign.id }
        state.reorderTab(a.id, relativeTo: b.id, after: true)
        check(state.tabs.firstIndex { $0.id == foreign.id } == foreignIndex, "other Spaces retain their positions")
        for layout in TabLayout.allCases {
            state.tabLayout = layout; state.sidebarVisible = true
            try? await Task.sleep(for: .milliseconds(350))
            // Reuse the same source identity repeatedly, as SwiftUI does after a row moves.
            for iteration in 0..<6 {
                let provider = TabDrag.provider(a.id)
                browser.chrome.beginTabDrag(a.id)
                let after = iteration.isMultiple(of: 2)
                let accepted = await withCheckedContinuation { continuation in
                    TabDrag.load(provider) { id in
                        continuation.resume(returning: state.reorderTab(id, relativeTo: b.id, after: after))
                    }
                }
                browser.chrome.endTabDrag()
                check(accepted, "\(layout) consecutive drag \(iteration + 1) accepts the same tab after it moves")
                let order = state.looseTabs.map(\.id)
                check(order.firstIndex(of: a.id) == (order.firstIndex(of: b.id) ?? -2) + (after ? 1 : -1),
                      "repeated drag places the tab on the requested side")
                try? await Task.sleep(for: .milliseconds(150))
                if let root = browser.window?.contentView {
                    let key = layout == .vertical ? "sidebar-tab-\(a.id)" : "regular-tab-\(a.id)"
                    if let frame = LayoutChecks.frames[key] {
                        let point = NSPoint(x: frame.midX, y: root.isFlipped ? frame.midY : root.bounds.height - frame.midY)
                        let hit = root.hitTest(root.convert(point, to: root.superview))
                        check(hit != nil && !(hit is WindowDragArea.DragView), "moved row remains reachable for clicks and another drag")
                    } else { check(false, "moved row has a visible frame") }
                }
            }
        }
        print("IKTEST tabreorderingchecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }
}

#endif
