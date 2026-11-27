#if DEBUG
import AppKit
import UniformTypeIdentifiers

/// What the list's drag checks share: the list on screen, a pretend drag (the real pointer is never moved), and ways to
/// drive the outline the way AppKit does.
@MainActor
struct OutlineDragRig {
    let state: BrowserState
    let window: NSWindow
    private let first: SidebarOutlineController
    /// The list in the window now: the sidebar may build its list again (as its rows come and go), and the old one is gone.
    var list: SidebarOutlineController { SidebarOutlineController.shown(in: window) ?? first }
    var outlineView: SidebarOutlineTable { list.outlineView }

    /// The list in this window's sidebar, or nil while it isn't on screen.
    init?(_ browser: BrowserWindowController) {
        guard let window = browser.window, let list = SidebarOutlineController.shown(in: window) else { return nil }
        self.state = browser.state
        self.window = window
        self.first = list
    }

    /// Runs a drag step from the run loop, as AppKit delivers drags, never inside a check's task: AppKit's drag handling
    /// may run the run loop itself, and doing that inside a task's job broke Swift's record of which actor is running
    /// (the next actor check crashed).
    func fromRunLoop<T>(_ body: @escaping @MainActor () -> T) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { MainActor.assumeIsolated { continuation.resume(returning: body()) } }
        }
    }

    func node(_ id: String) -> OutlineNode? { list.nodeForCheck(id) }
    func row(_ id: String) -> Int { node(id).map { outlineView.row(forItem: $0) } ?? -1 }
    func rowIDs() -> [String] { list.outline.rows.map(\.id) }

    /// A point in the window over a row, `fraction` of the way down it.
    func point(row: Int, fraction: CGFloat) -> NSPoint {
        outlineView.scrollRowToVisible(row)
        let rect = outlineView.rect(ofRow: row)
        return outlineView.convert(NSPoint(x: rect.midX, y: rect.minY + rect.height * fraction), to: nil)
    }

    /// Drops with the pointer at `point` (a point in the window) in one move, through the outline's own drag path: the
    /// drag enters there and is dropped, and the drop concludes (AppKit's gap state would be left behind otherwise).
    func drop(_ drag: PretendDrag, at point: NSPoint) async -> Bool {
        drag.location = point
        return await fromRunLoop {
            guard outlineView.draggingEntered(drag) != [] else {
                outlineView.draggingExited(drag)
                return false
            }
            return self.drop(drag)
        }
    }

    /// The rows a drag carries, as the model has them now.
    func moving(_ drag: PretendDrag) -> [SidebarOutline.Row] {
        let pasteboard = drag.draggingPasteboard
        if let data = pasteboard.data(forType: NSPasteboard.PasteboardType(UTType.ikagoGroup.identifier)),
           let group = try? JSONDecoder().decode(GroupDrag.self, from: data) { return state.sidebarRows(group: group.id) }
        if let data = pasteboard.data(forType: NSPasteboard.PasteboardType(UTType.ikagoTab.identifier)),
           let tab = try? JSONDecoder().decode(TabDrag.self, from: data) { return state.sidebarRows(dragging: [tab.id]) }
        return []
    }

    /// Where a drop with the pointer at `point` should land, by the rule as people see it, from the rows on screen now:
    /// the upper half of a row is before it; the lower half of a group's header is into the group; the lower half of a
    /// tab row, a gap, or the space between rows is before the row below; below every row is the end.
    func expectedTarget(at point: NSPoint) -> SidebarOutline.Target {
        let pointer = outlineView.convert(point, from: nil)
        let rows = (0..<outlineView.numberOfRows).compactMap { row in
            (outlineView.item(atRow: row) as? OutlineNode).map { (node: $0, rect: outlineView.rect(ofRow: row)) }
        }
        for (index, row) in rows.enumerated() where row.rect.minY <= pointer.y && pointer.y < row.rect.maxY {
            if pointer.y < row.rect.midY { return .before(row.node.id) }
            if let group = row.node.row.groupID { return .into(group) }
            return index + 1 < rows.count ? .before(rows[index + 1].node.id) : .end
        }
        return rows.first { $0.rect.minY >= pointer.y }.map { .before($0.node.id) } ?? .end
    }

    /// The model's rows after `moving` dropped at `target`, as the one rule says (nil: refused).
    func expectedOutline(_ moving: [SidebarOutline.Row], at target: SidebarOutline.Target) -> SidebarOutline? {
        let now = state.sidebarOutline
        return now.place(for: moving, at: target).map { now.moving(moving, to: $0) }
    }

    /// Drags the way a hand does, through the outline's own drag path: in steps from `start` toward a row's upper or
    /// lower part, following the row as the gap moves it, then drops there. `shot`: the window is saved just before the
    /// drop, with the gap open. Returns whether the list took it.
    func drag(_ drag: PretendDrag, from start: NSPoint, over id: String, upper: Bool, shot name: String? = nil) async -> Bool {
        drag.location = start
        _ = await fromRunLoop { outlineView.draggingEntered(drag) }
        for index in 1...12 {
            let target = point(over: id, upper: upper)
            let t = CGFloat(index) / 12
            drag.location = NSPoint(x: start.x + (target.x - start.x) * t, y: start.y + (target.y - start.y) * t)
            _ = await fromRunLoop { outlineView.draggingUpdated(drag) }
        }
        // Settle on the row where it is now (the gap may have moved it), as an eye on the row would.
        for _ in 0..<3 {
            drag.location = point(over: id, upper: upper)
            _ = await fromRunLoop { outlineView.draggingUpdated(drag) }
            try? await Task.sleep(for: .milliseconds(120))
        }
        if let name { self.shot(name) }
        let shown = list.shownDropForCheck
        let took = await fromRunLoop { self.drop(drag) }
        if !took {
            print("IKTEST rig drop not taken: shown \(String(describing: shown)), pointer over \(expectedTarget(at: drag.location)), lists \(SidebarOutlineController.made.allObjects.count)")
        }
        return took
    }

    /// One random drag over the list, through the outline's own drag path (a crash walk's step): a row on screen, tab or
    /// group, dragged in steps to a random place on screen and dropped.
    func randomDrag(seed: UInt64) async {
        var random = SplitMix(seed: seed)
        let rows = (0..<outlineView.numberOfRows).compactMap { (outlineView.item(atRow: $0) as? OutlineNode)?.row }
            .filter { $0.kind != .divider }
        guard let moving = rows.randomElement(using: &random) else { return }
        let drag = moving.groupID.map { PretendDrag(group: $0, window: window) } ?? PretendDrag(tab: moving.tabIDs.first, window: window)
        func anywhere() -> NSPoint {
            let visible = outlineView.visibleRect
            let y = visible.minY + CGFloat(random.next() % UInt64(max(1, Int(visible.height))))
            return outlineView.convert(NSPoint(x: visible.midX, y: y), to: nil)
        }
        let start = anywhere(), end = anywhere()
        drag.location = start
        _ = await fromRunLoop { outlineView.draggingEntered(drag) }
        for index in 1...6 {
            let t = CGFloat(index) / 6
            drag.location = NSPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
            _ = await fromRunLoop { outlineView.draggingUpdated(drag) }
        }
        _ = await fromRunLoop { self.drop(drag) }
    }

    /// The rows' ids as a tree, for comparing outlines (groups opening is not a difference).
    func tree(_ outline: SidebarOutline) -> String {
        func describe(_ rows: [SidebarOutline.Row]) -> String {
            rows.map { $0.id.suffix(4) + ($0.children.isEmpty ? "" : "[" + describe($0.children) + "]") }.joined(separator: " ")
        }
        return describe(outline.rows)
    }

    /// A point over a row: its upper part (before it), or its lower part (into a group, or before the next row).
    func point(over id: String, upper: Bool) -> NSPoint { point(row: row(id), fraction: upper ? 0.25 : 0.75) }

    /// The window as it looks now, saved as `<IKAGO_SHOTS>/<name>.png` when that folder is set.
    func shot(_ name: String) {
        guard let folder = DebugEnvironment.value("IKAGO_SHOTS"), let content = window.contentView else { return }
        outlineView.layoutSubtreeIfNeeded()
        _ = PeekShot.measure(content, window: window, save: folder + "/" + name + ".png")
    }

    /// The outline's own drag path, as AppKit runs it: the pointer enters at `start`, moves to `location`, and the row is
    /// dropped there (the drop and its conclusion, which the outline needs to close its gap). The outline offers the place.
    /// Returns whether it took the drop.
    func dragAndDrop(_ drag: PretendDrag, from start: NSPoint? = nil, to location: NSPoint) async -> Bool {
        if let start { drag.location = start }
        _ = await fromRunLoop { outlineView.draggingEntered(drag) }
        drag.location = location
        let operation = await fromRunLoop { outlineView.draggingUpdated(drag) }
        guard operation != [] else {
            await fromRunLoop { outlineView.draggingExited(drag) }
            return false
        }
        return await fromRunLoop { drop(drag) }
    }

    /// Takes the drop the outline last allowed and ends the drag, as AppKit does: the drop, its conclusion and the end of the
    /// drag (if the outline has a use for it).
    func drop(_ drag: PretendDrag) -> Bool {
        let took = outlineView.performDragOperation(drag)
        outlineView.concludeDragOperation(drag)
        if outlineView.responds(to: #selector(NSDraggingDestination.draggingEnded(_:))) { outlineView.draggingEnded(drag) }
        return took
    }

    /// The rows the list shows, in a line, for a failure's message: groups with their rows in brackets.
    func summary(of outline: SidebarOutline? = nil) -> String {
        func describe(_ rows: [SidebarOutline.Row]) -> String {
            rows.map { row in
                switch row.kind {
                case .divider: "NEW"
                case .group(let id): "G\(id.prefix(4))[\(describe(row.children))]"
                case .tabs(let ids): ids.map { "T" + $0.prefix(4) }.joined(separator: "+")
                }
            }.joined(separator: " ")
        }
        return describe((outline ?? list.expectedOutlineForCheck).rows)
    }

    /// The group ids the model has open: the groups the list should show open.
    var openGroups: Set<String> { Set(state.spaceFolders.filter(\.isOpen).map(\.id)) }

    /// What the list shows differs from what the model says, or is empty when it follows it: the rows on screen in order,
    /// each group's rows as the outline holds them (open or shut), and every row's depth and parent.
    func problems() -> [String] {
        let expected = list.expectedOutlineForCheck
        var out: [String] = []
        var flat: [(id: String, depth: Int)] = []
        func visit(_ rows: [SidebarOutline.Row], _ depth: Int) {
            for row in rows {
                flat.append((row.id, depth))
                if let id = row.groupID, openGroups.contains(id) { visit(row.children, depth + 1) }
            }
        }
        visit(expected.rows, 0)
        if Set(flat.map(\.id)).count != flat.count { out.append("a row is shown twice") }
        outlineView.layoutSubtreeIfNeeded()
        let shown = (0..<outlineView.numberOfRows).map { outlineView.item(atRow: $0) as? OutlineNode }
        if shown.map({ $0?.id }) != flat.map(\.id) {
            out.append("rows on screen \(shown.map { $0?.id.suffix(4) ?? "?" }) differ from the model's \(flat.map { $0.id.suffix(4) })")
        } else {
            for (node, want) in zip(shown, flat) where node.map(outlineView.level(forItem:)) != want.depth {
                out.append("\(want.id) is at depth \(node.map(outlineView.level(forItem:)) ?? -1), the model says \(want.depth)")
            }
        }
        // The outline's cached heights are the rows' heights (a stale one crashes AppKit when a drag opens its gap).
        for (row, node) in shown.enumerated() {
            guard let node else { continue }
            let cached = outlineView.rect(ofRow: row).height - outlineView.intercellSpacing.height
            if abs(cached - list.heightForCheck(node)) > 0.5 { out.append("\(node.id.suffix(4)) is \(cached) tall in the outline, \(list.heightForCheck(node)) in the list") }
        }
        func walk(_ parent: OutlineNode?, _ rows: [SidebarOutline.Row]) {
            let held = (0..<outlineView.numberOfChildren(ofItem: parent)).map { (outlineView.child($0, ofItem: parent) as? OutlineNode)?.id }
            if held != rows.map(\.id) { out.append("the outline holds \(held.map { $0?.suffix(4) ?? "?" }) under \(parent?.id.suffix(4) ?? "the top"), the model \(rows.map { $0.id.suffix(4) })") }
            for row in rows {
                guard row.groupID != nil, let node = self.node(row.id) else { continue }
                if outlineView.row(forItem: node) >= 0, outlineView.parent(forItem: node) as? OutlineNode !== parent { out.append("\(row.id) has the wrong parent") }
                if outlineView.row(forItem: node) >= 0, outlineView.isItemExpanded(node) != openGroups.contains(row.groupID ?? "") { out.append("\(row.id) is open or shut against the model") }
                // A shut group holds no rows.
                walk(node, row.isOpen ? row.children : [])
            }
        }
        walk(nil, expected.rows)
        return out
    }

    /// Waits for the list to show what the model holds now (it follows the model on SwiftUI's next update) and returns what
    /// still differs, if anything.
    func settle() async -> [String] {
        var found: [String] = []
        for _ in 0..<80 {
            try? await Task.sleep(for: .milliseconds(15))
            found = list.outline == list.expectedOutlineForCheck ? problems()
                : ["the list has not followed the model: it shows \(summary(of: list.outline)), the model \(summary(of: list.expectedOutlineForCheck))"]
            if found.isEmpty { break }
        }
        return found
    }
}

/// A drag carrying a tab or a group, at a point the check sets.
final class PretendDrag: NSObject, NSDraggingInfo {
    /// Every drag made. The outline keeps its last one without holding it (the gap animation reads it later, on the display
    /// link's thread): one freed too soon is read after it is freed.
    nonisolated(unsafe) private static var made: [PretendDrag] = []
    var location = NSPoint.zero
    let pasteboard: NSPasteboard
    weak var window: NSWindow?

    init(tab: String? = nil, group: String? = nil, window: NSWindow) {
        // One pasteboard for every pretend drag: each named one lives in the system's pasteboard server until released.
        pasteboard = NSPasteboard(name: NSPasteboard.Name("app.ikago.check.drag"))
        pasteboard.clearContents()
        if let tab, let data = try? JSONEncoder().encode(TabDrag(id: tab)) {
            pasteboard.setData(data, forType: NSPasteboard.PasteboardType(UTType.ikagoTab.identifier))
        }
        if let group, let data = try? JSONEncoder().encode(GroupDrag(id: group)) {
            pasteboard.setData(data, forType: NSPasteboard.PasteboardType(UTType.ikagoGroup.identifier))
        }
        self.window = window
        super.init()
        Self.made.append(self)
    }

    var draggingDestinationWindow: NSWindow? { window }
    var draggingSourceOperationMask: NSDragOperation { [.move, .generic] }
    var draggingLocation: NSPoint { location }
    var draggedImageLocation: NSPoint { location }
    var draggedImage: NSImage? { nil }
    var draggingPasteboard: NSPasteboard { pasteboard }
    var draggingSource: Any? { nil }
    /// Each drag its own, as AppKit numbers drag sessions.
    let draggingSequenceNumber = PretendDrag.made.count + 1
    func slideDraggedImage(to screenPoint: NSPoint) {}
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions = [], for view: NSView?,
                                classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:],
                                using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    func resetSpringLoading() {}
}
/// A seeded generator, so a failing run can be repeated.
struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
#endif
