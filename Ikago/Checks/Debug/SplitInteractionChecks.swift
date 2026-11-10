#if DEBUG
import AppKit

@MainActor
enum SplitInteractionChecks {
    static func run(_ browser: BrowserWindowController) async {
        var failures = 0
        func check(_ value: Bool, _ title: String) {
            print("IKTEST splitinteraction \(value ? "PASS" : "FAIL") \(title)")
            if !value { failures += 1 }
        }
        let root = FileManager.default.temporaryDirectory.appending(path: "IkagoSplitChecks-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        for edge in [SplitEdge.left, .right, .top, .bottom] {
            let store = SessionStore(directory: root.appending(path: UUID().uuidString))
            let state = BrowserState(store: store)
            let a = state.newTab(url: "https://a.example")!
            let b = state.newTab(url: "https://b.example", select: false)!
            state.splitWithDropped(a.id, edge: edge)
            let group = state.splitGroup(of: a.id) ?? []
            let empty = group.first { state.tab($0)?.url == InternalPage.splitEmpty.url }
            check(group.count == 2 && empty != nil && state.activeTabID == a.id, "active tab opens empty split on \(edge)")
            check(edge.isLeading ? group.first == a.id : group.last == a.id, "dragged active tab occupies requested side")
            check(state.splitLayout == (edge.isHorizontalAxis ? .columns : .rows), "drop chooses matching axis")
            state.saveNow()
            let restored = BrowserState(store: store)
            // Session validation covers the internal placeholder URL and split membership.
            do { try state.snapshot().validate(); check(true, "empty split is a valid session") }
            catch { check(false, "empty split session validation") }
            check(restored.splits == state.splits && restored.tabs.map(\.saved) == state.tabs.map(\.saved), "empty split restores")
            if let empty {
                state.fillEmptySplit(empty, with: b.id)
                check(state.splitGroup(of: b.id) == group.map { $0 == empty ? b.id : $0 } && state.tab(empty) == nil,
                      "drop fills exact empty slot without changing layout")
            }
            state.separate(b.id)
            check(state.splits.isEmpty && state.tab(b.id) != nil, "removing pane keeps tab open")
        }
        let capacity = BrowserState(store: SessionStore(directory: root.appending(path: "capacity")))
        let members = (0..<6).map { capacity.newTab(url: "https://pane\($0).example")!.id }
        capacity.splits = [Array(members.prefix(4)), Array(members.suffix(2))]
        capacity.select(members[0])
        let before = capacity.splits
        capacity.splitWithDropped(members[4], edge: .right)
        check(capacity.splits == before, "full target does not dismantle source group")
        let state = browser.state
        let originalIDs = Set(state.tabs.map(\.id)), active = state.activeTabID
        let layout = state.tabLayout, rounded = state.barRounded, splitLayout = state.splitLayout
        defer {
            for tab in state.tabs where !originalIDs.contains(tab.id) { state.closeTab(tab.id, removingPin: true) }
            state.tabLayout = layout; state.barRounded = rounded; state.splitLayout = splitLayout
            if let active { state.select(active) }
        }
        browser.palette.onDismiss()
        for (mode, floating) in [(TabLayout.vertical, false), (.horizontal, false), (.horizontal, true)] {
            state.tabLayout = mode; state.barRounded = floating
            let a = state.newTab(url: InternalPage.history.url)!, b = state.newTab(url: InternalPage.bookmarks.url, select: false)!
            let provider = TabDrag.provider(b.id)
            browser.chrome.beginTabDrag(b.id)
            browser.chrome.endTabDrag()
            await withCheckedContinuation { continuation in
                TabDrag.load(provider) { id in
                    state.splitWithDropped(id, edge: .right)
                    continuation.resume()
                }
            }
            check(state.splitGroup(of: a.id)?.contains(b.id) == true, "\(mode) drop survives cleared drag UI state")
            try? await Task.sleep(for: .milliseconds(250))
            if let controller = browser.content.controller(for: b.id) {
                controller.setHeaderVisible(true)
                controller.header?.layoutSubtreeIfNeeded()
                check(controller.header?.closeButton.superview === controller.header && controller.header?.handle.superview === controller.header,
                      "native close button and drag handle are separate hit targets")
                if let header = controller.header {
                    let point = header.closeButton.convert(NSPoint(x: 13, y: 11), to: controller.hostView.superview)
                    let hit = controller.hostView.hitTest(point)
                    check(hit === header.closeButton || hit?.isDescendant(of: header.closeButton) == true, "header close button receives actual pane hit testing")
                }
                controller.header?.closeButton.performClick(nil)
                check(state.splitGroup(of: b.id) == nil && state.tab(b.id) != nil, "\(mode) actual header button removes pane and retains tab")
            } else { check(false, "pane controller exists") }
            state.closeTab(a.id, removingPin: true); state.closeTab(b.id, removingPin: true)
        }
        failures += await NativeSplitDropChecks.run(browser)
        print("IKTEST splitinteractionchecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }
}
#endif
