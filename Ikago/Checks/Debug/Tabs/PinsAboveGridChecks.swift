#if DEBUG
import AppKit
import UniformTypeIdentifiers

/// Pinned rows above the essentials, in the one sidebar list, through the outline's own drag path: the essentials are a
/// row whose band is the list's, so a tab dragged over it goes above them, a second lands after the first, and one
/// dragged back below leaves; one dropped on the grid becomes an essential, before the tile under it. A real drag over
/// any of the row reaches the list (views inside a row never see drops). With the address in the sidebar and above
/// the page. `IKAGO_SHOTS=<folder>` saves the sidebar before, with pins above, after.
@MainActor
enum PinsAboveGridChecks {
    static func run(_ browser: BrowserWindowController) async {
        var failures = 0
        func check(_ value: Bool, _ title: String) {
            print("IKTEST pinsabovegrid \(value ? "PASS" : "FAIL") \(title)")
            if !value { failures += 1 }
        }
        let state = browser.state
        LayoutSwitch.set(tabs: false, state: state)
        state.browserPreferences.sidebarCompact = nil
        state.browserPreferences.showPinnedGrid = true
        state.sidebarVisible = true
        let tabs = (0..<6).compactMap { state.newTab(url: "about:blank#above\($0)", select: false) }
        // Only these: tabs earlier checks left make the list long enough to scroll while the drags below move.
        let mine = Set(tabs.map(\.id))
        for tab in state.tabs where tab.spaceID == state.activeSpaceID && !mine.contains(tab.id) {
            state.closeTab(tab.id, removingPin: true)
        }
        let (essential, pin, l1, l2) = (tabs[0], tabs[1], tabs[2], tabs[3])
        state.movePin(essential.id, intoGrid: true)
        state.movePin(pin.id, intoGrid: false)
        try? await Task.sleep(for: .milliseconds(800))
        guard let rig = OutlineDragRig(browser) else {
            check(false, "the sidebar list is on screen"); finish(failures); return
        }
        // From the top of the list: checks before this one may leave it scrolled, the essentials floating over it.
        rig.outlineView.scrollRowToVisible(0)
        try? await Task.sleep(for: .milliseconds(200))
        rig.shot("pins-1-before")

        // A tab dragged up and down the list: the essentials stay where they are (they jumped sideways under the pointer).
        do {
            func gridX() -> CGFloat? {
                let row = rig.row("essentials")
                guard row >= 0, let cell = rig.outlineView.view(atColumn: 0, row: row, makeIfNecessary: false) else { return nil }
                return cell.convert(cell.bounds, to: nil).minX
            }
            let before = gridX()
            let drag = PretendDrag(tab: l2.id, window: rig.window)
            var seen: [CGFloat] = []
            drag.location = rig.point(over: "tab:" + l1.id, upper: true)
            _ = await rig.fromRunLoop { rig.outlineView.draggingEntered(drag) }
            for step in 0..<24 {
                let ids = ["tab:" + l1.id, "tab:" + l2.id, "divider", "essentials", "tab:" + pin.id]
                drag.location = rig.point(over: ids[step % ids.count], upper: step % 2 == 0)
                _ = await rig.fromRunLoop { rig.outlineView.draggingUpdated(drag) }
                try? await Task.sleep(for: .milliseconds(60))
                if let x = gridX() { seen.append(x) }
            }
            _ = await rig.fromRunLoop { rig.outlineView.draggingExited(drag) }
            // The drag scrolled the list near its edges, as a real one does: back to the top for what follows.
            rig.outlineView.scroll(.zero)
            try? await Task.sleep(for: .milliseconds(200))
            check(before != nil && seen.allSatisfy { abs($0 - before!) < 0.5 },
                  "the essentials hold still while a tab is dragged up and down (at \(seen.map { Int($0) }), from \(before.map { Int($0) } ?? -1))")
        }
        check(rig.rowIDs().first == "essentials", "the essentials are the list's first row")

        /// A point in the window over the essentials row: its band (`band`) or the middle of its grid.
        func overEssentials(band: Bool) -> NSPoint {
            let rect = rig.outlineView.rect(ofRow: rig.row("essentials"))
            let y = band ? (rig.outlineView.isFlipped ? rect.minY + 4 : rect.maxY - 4) : rect.midY
            return rig.outlineView.convert(NSPoint(x: rect.midX, y: y), to: nil)
        }
        /// The view a real tab drag at `point` reaches, as AppKit finds a drop's destination: the view under it in the
        /// window, then up to the first that takes tabs.
        func reached(_ point: NSPoint) -> NSView? {
            let type = NSPasteboard.PasteboardType(UTType.ikagoTab.identifier)
            var view = rig.window.contentView?.superview.flatMap { $0.hitTest($0.convert(point, from: nil)) }
            while let current = view, !current.registeredDraggedTypes.contains(type) { view = current.superview }
            // The essentials float in a view AppKit keeps over the list: the list's scroll view takes drops there for it.
            if let scroll = view as? OutlineScrollView { return scroll.documentView }
            return view
        }

        let addressAbove = state.browserPreferences.addressAbovePage
        for above in [false, true] {
            state.browserPreferences.addressAbovePage = above ? true : nil
            try? await Task.sleep(for: .milliseconds(600))
            let tag = above ? " (address above the page)" : ""
            check(reached(overEssentials(band: true)) === rig.outlineView, "a drag over the band reaches the list\(tag)")
            check(reached(overEssentials(band: false)) === rig.outlineView, "a drag over the grid reaches the list too\(tag)")
        }
        state.browserPreferences.addressAbovePage = addressAbove
        try? await Task.sleep(for: .milliseconds(600))

        // Over the band: above the essentials.
        check(await rig.drag(PretendDrag(tab: l1.id, window: rig.window), from: rig.point(over: "tab:" + l1.id, upper: true),
                             over: "essentials", upper: true), "the band above the essentials takes a tab")
        try? await Task.sleep(for: .milliseconds(500))
        check(l1.pinned && l1.pinAboveGrid && rig.rowIDs().prefix(2) == ["tab:" + l1.id, "essentials"], "it is a pin above them")

        // Below the first pin above them is still above them.
        check(await rig.drag(PretendDrag(tab: pin.id, window: rig.window), from: rig.point(over: "tab:" + pin.id, upper: true),
                             over: "tab:" + l1.id, upper: false, shot: "pins-2-dragging"), "a pinned row moves up there")
        try? await Task.sleep(for: .milliseconds(500))
        check(rig.rowIDs().prefix(3) == ["tab:" + l1.id, "tab:" + pin.id, "essentials"] && pin.pinAboveGrid, "it lands after the first")
        rig.shot("pins-3-above")

        // Back down into the list.
        check(await rig.drag(PretendDrag(tab: l1.id, window: rig.window), from: rig.point(over: "tab:" + l1.id, upper: true),
                             over: "tab:" + l2.id, upper: true), "a pin above them moves back down")
        try? await Task.sleep(for: .milliseconds(500))
        check(!l1.pinned && !l1.pinAboveGrid && rig.rowIDs().prefix(2) == ["tab:" + pin.id, "essentials"], "it is a loose tab again")
        // Onto the grid: an essential, before the tile under the pointer's left half.
        check(await rig.drag(PretendDrag(tab: l2.id, window: rig.window), from: rig.point(over: "tab:" + l2.id, upper: true),
                             over: "essentials", upper: false), "the grid takes a tab")
        try? await Task.sleep(for: .milliseconds(500))
        check(state.sidebarGridPinnedTabs.map(\.id).contains(l2.id) && !rig.rowIDs().contains("tab:" + l2.id),
              "it is an essential, and out of the list \(state.sidebarGridPinnedTabs.map(\.id))")
        check(rig.problems().isEmpty, "the list matches the model \(rig.problems())")
        rig.shot("pins-4-after")
        finish(failures)
    }

    private static func finish(_ failures: Int) {
        print("IKTEST pinsabovegridchecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }
}
#endif
