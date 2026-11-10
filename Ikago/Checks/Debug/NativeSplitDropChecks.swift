#if DEBUG
import AppKit

@MainActor
enum NativeSplitDropChecks {
    static func run(_ browser: BrowserWindowController) async -> Int {
        var failures = 0
        func check(_ value: Bool, _ message: String) {
            print("IKTEST nativesplitdrop \(value ? "PASS" : "FAIL") \(message)")
            if !value { failures += 1 }
        }
        func find(_ view: NSView) -> SplitDropTargetView? {
            if let target = view as? SplitDropTargetView { return target }
            return view.subviews.lazy.compactMap { find($0) }.first
        }
        let state = browser.state
        let original = Set(state.tabs.map(\.id)), active = state.activeTabID
        let layout = state.tabLayout, rounded = state.barRounded
        defer {
            browser.chrome.endTabDrag()
            for tab in state.tabs where !original.contains(tab.id) { state.closeTab(tab.id, removingPin: true) }
            state.tabLayout = layout; state.barRounded = rounded
            if let active { state.select(active) }
        }
        browser.palette.onDismiss()
        for (mode, floating) in [(TabLayout.vertical, false), (.horizontal, false), (.horizontal, true)] {
            state.tabLayout = mode; state.barRounded = floating
            let a = state.newTab(url: "https://native-drop.invalid")!
            try? await Task.sleep(for: .milliseconds(300))
            guard let root = browser.window?.contentView, var target = find(root), let window = target.window else {
                check(false, "permanently mounted target exists"); continue
            }
            check(target.registeredDraggedTypes.contains(SplitDropTargetView.pasteboardType), "target registers native tab type before drag starts")
            var center = NSPoint(x: target.bounds.midX, y: target.bounds.midY)
            let parentPoint = target.convert(center, to: target.superview)
            check(target.hitTest(parentPoint) == nil, "inactive target lets normal page input through")
            browser.chrome.beginTabDrag(a.id)
            try? await Task.sleep(for: .milliseconds(50))
            let rootPoint = target.convert(center, to: root.superview)
            let routed = root.hitTest(rootPoint) as? SplitDropTargetView
            check(routed?.active == true, "\(mode) floating=\(floating) drag hit testing reaches native destination above web view")
            guard let routed else { continue }
            target = routed
            center = NSPoint(x: target.bounds.midX, y: target.bounds.midY)
            let pasteboard = NSPasteboard.withUniqueName()
            pasteboard.setData(try! JSONEncoder().encode(TabDrag(id: a.id)), forType: SplitDropTargetView.pasteboardType)
            let info = SplitDragInfo(pasteboard: pasteboard, window: window)
            var observed: SplitEdge?
            let update = target.onEdge
            target.onEdge = { observed = $0; update($0) }
            for (edge, point) in [(SplitEdge.left, NSPoint(x: 2, y: center.y)), (.right, NSPoint(x: target.bounds.width - 2, y: center.y)),
                                  (.top, NSPoint(x: center.x, y: 2)), (.bottom, NSPoint(x: center.x, y: target.bounds.height - 2))] {
                info.draggingLocation = target.convert(point, to: nil)
                check(target.draggingEntered(info) == .move && observed == edge, "native enter activates \(edge) preview")
                check(target.draggingUpdated(info) == .move && observed == edge, "native update keeps \(edge) drop accepted")
                target.draggingExited(info)
                check(observed == nil, "exit clears preview")
            }
            info.draggingLocation = target.convert(NSPoint(x: 2, y: center.y), to: nil)
            info.draggingSourceOperationMask = .copy
            check(target.draggingUpdated(info) == .copy, "copy-only drag sources are accepted without requiring unsupported move operation")
            info.draggingSourceOperationMask = .move
            check(target.prepareForDragOperation(info), "native prepare accepts valid payload")
            target.active = false // Simulate source cleanup arriving before performDrop.
            check(target.performDragOperation(info) && state.splitGroup(of: a.id)?.count == 2, "native drop commits active-tab split even after drag UI cleanup")
            pasteboard.clearContents()
            pasteboard.setString("https://example.com", forType: .string)
            check(!target.prepareForDragOperation(info) && !target.performDragOperation(info), "ordinary page/text drags cannot split tabs")
            pasteboard.releaseGlobally()
            for tab in state.tabs where !original.contains(tab.id) { state.closeTab(tab.id, removingPin: true) }
        }
        return failures
    }
}

@MainActor
private final class SplitDragInfo: NSObject, NSDraggingInfo {
    let draggingPasteboard: NSPasteboard
    let draggingDestinationWindow: NSWindow?
    var draggingLocation = NSPoint.zero
    var draggingSourceOperationMask: NSDragOperation = .move
    var draggedImageLocation: NSPoint { draggingLocation }
    nonisolated var draggedImage: NSImage? { nil }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 1 }
    var draggingFormation: NSDraggingFormation = .none
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    init(pasteboard: NSPasteboard, window: NSWindow) { draggingPasteboard = pasteboard; draggingDestinationWindow = window }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    nonisolated override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
    func resetSpringLoading() {}
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions = [], for view: NSView?, classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:], using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
}
#endif
