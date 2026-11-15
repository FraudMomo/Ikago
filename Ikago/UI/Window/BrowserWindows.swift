import AppKit

/// Ikago's regular windows (private windows live apart, in AppDelegate). Each has its own tabs; Spaces, settings,
/// history and bookmarks are shared (`BrowserState+Windows`). The first window's state saves the session, the other
/// windows included. Tabs move between windows with their live pages: Window ▸ Move Tab to New Window, dragging a tab
/// out of every window (a new window where it is dropped), or dropping it on another window's tabs.
@MainActor
enum BrowserWindows {
    /// The window whose state saves the session.
    static weak var primary: BrowserWindowController?
    /// The other regular windows, kept alive here until they close.
    private(set) static var others: [BrowserWindowController] = []
    /// Windows closing because the first window took over their tabs (`handOver`).
    private static var handedOver = Set<ObjectIdentifier>()

    static var all: [BrowserWindowController] { [primary].compactMap { $0 } + others }

    /// The regular window in front, for links from other apps and new windows.
    static var frontmost: BrowserWindowController? {
        NSApp.orderedWindows.lazy.compactMap { $0.windowController as? BrowserWindowController }
            .first { !$0.state.isPrivate && !$0.state.isFrozen } ?? primary
    }

    static func owner(of tabID: String) -> BrowserWindowController? { all.first { $0.state.tab(tabID) != nil } }
    static func controller(for state: BrowserState) -> BrowserWindowController? { all.first { $0.state === state } }

    /// A regular window under a point on screen, if any Ikago window is there at all.
    static func window(at point: NSPoint) -> NSWindow? {
        NSApp.orderedWindows.first { $0.isVisible && !$0.isMiniaturized && $0.frame.contains(point) }
    }

    /// Opens a window after the first: a saved one (at launch) or a new, empty one beside the front window.
    @discardableResult
    static func open(_ session: WindowSession? = nil, frame: NSRect? = nil, show: Bool = true) -> BrowserWindowController? {
        guard let primary, !primary.state.isFrozen, others.count < WindowSession.maxWindows else { return nil }
        let state = BrowserState(windowOf: primary.state, session: session)
        let controller = BrowserWindowController(state: state)
        others.append(controller)
        primary.state.windowStates = others.map(\.state)
        if let frame = frame ?? session?.screenFrame { controller.window?.setFrame(frame, display: false) }
        else if let front = frontmost?.window, front !== controller.window {
            controller.window?.setFrame(front.frame.offsetBy(dx: 28, dy: -28), display: false)
        }
        state.windowFrame = controller.window?.frame
        primary.state.scheduleSave()
        if show { controller.showWindow(nil) }
        return controller
    }

    /// The saved windows of a restored session, after the first window opened.
    static func restore(_ windows: [WindowSession]) {
        var taken = Set(primary?.state.tabs.map(\.id) ?? [])
        for window in windows where !window.tabs.isEmpty && window.isValid(besides: taken) {
            taken.formUnion(window.tabs.map(\.id))
            open(window)
        }
    }

    /// Moves a tab, with its live page, into `destination` and selects it there. A window left with no tabs closes.
    @discardableResult
    static func move(_ id: String, to destination: BrowserWindowController, space: UUID? = nil) -> Bool {
        guard let source = owner(of: id), source !== destination, !source.state.isFrozen, !destination.state.isFrozen,
              source.state.isPrivate == destination.state.isPrivate else { return false }
        let released = source.content.release(id)
        guard let tab = source.state.detachTab(id) else { return false }
        destination.content.adopt(tab, page: released?.page, popup: released?.popup ?? false)
        destination.state.adoptTab(tab, space: space)
        if source.state.tabs.isEmpty { source.window?.performClose(nil) }
        return true
    }

    /// Window ▸ Move Tab to New Window: the tab in a new window beside this one.
    static func moveToNewWindow(_ id: String, from source: BrowserWindowController) {
        guard canMoveOut(id, from: source), let window = open(frame: source.window?.frame.offsetBy(dx: 28, dy: -28), show: false) else { return }
        move(id, to: window)
        window.showWindow(nil)
    }

    /// Several tabs together in a new window, in their order. The window they leave keeps at least one tab.
    static func moveToNewWindow(_ ids: [String], from source: BrowserWindowController, frame: NSRect? = nil) {
        let ids = ids.filter { source.state.tab($0) != nil }
        guard !ids.isEmpty, !source.state.isPrivate, ids.count < source.state.tabs.count,
              let window = open(frame: frame ?? source.window?.frame.offsetBy(dx: 28, dy: -28), show: false) else { return }
        for id in ids { move(id, to: window) }
        if let first = ids.first { window.state.select(first) }
        window.showWindow(nil)
    }

    /// A tab dragged out of every Ikago window: a new window with the tab under the pointer. Dragging a
    /// window's only tab out moves the window there instead.
    static func tearOff(_ id: String, from source: BrowserWindowController, at point: NSPoint, with companions: [String] = []) {
        guard !source.state.isPrivate, !source.state.isFrozen, source.state.tab(id) != nil, let current = source.window else { return }
        var frame = NSRect(x: point.x - 120, y: point.y - current.frame.height + 18, width: current.frame.width, height: current.frame.height)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? current.screen {
            let visible = screen.visibleFrame
            frame.size.width = min(frame.width, visible.width)
            frame.size.height = min(frame.height, visible.height)
            frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
            frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        }
        let order = source.state.navigationOrder.map(\.id)
        let ids = ([id] + companions.filter { $0 != id && source.state.tab($0) != nil })
            .sorted { (order.firstIndex(of: $0) ?? .max) < (order.firstIndex(of: $1) ?? .max) }
        guard ids.count < source.state.tabs.count, primary != nil else {
            current.setFrame(frame, display: true)
            return
        }
        moveToNewWindow(ids, from: source, frame: frame)
        BrowserWindows.owner(of: id)?.state.select(id)
    }

    /// A tab can leave its window when the window has another tab to keep (Chrome greys the command out otherwise).
    static func canMoveOut(_ id: String, from source: BrowserWindowController) -> Bool {
        !source.state.isPrivate && source.state.tab(id) != nil && source.state.tabs.count > 1 && primary != nil
    }

    /// A tab dropped on a window it isn't in: brought over first, so the drop then places it like any of its own tabs.
    static func bring(_ id: String, into state: BrowserState) {
        guard state.tab(id) == nil, let destination = controller(for: state) else { return }
        move(id, to: destination, space: state.activeSpaceID)
    }

    /// Closing the first window while others are open: it takes over another window's tabs and place, and that window
    /// goes, so the window the person closed is the one that disappears while the first window's state keeps saving.
    /// Returns false when there is no other window (the first window then closes as before).
    static func handOver(closing primary: BrowserWindowController) -> Bool {
        guard primary === self.primary, let other = others.last, let window = other.window else { return false }
        for tab in other.state.tabs {
            guard let released = other.content.release(tab.id) else { continue }
            if released.page != nil { primary.content.adopt(tab, page: released.page, popup: released.popup) }
        }
        primary.state.takeWindow(from: other.state)
        primary.window?.setFrame(window.frame, display: true)
        handedOver.insert(ObjectIdentifier(other))
        window.close()
        return true
    }

    /// A window after the first closed: its tabs, and the ones it had closed, join recently closed, so ⌘⇧T can bring
    /// them back.
    static func closed(_ controller: BrowserWindowController) {
        guard let index = others.firstIndex(where: { $0 === controller }) else { return }
        others.remove(at: index)
        guard let primary else { return }
        primary.state.windowStates = others.map(\.state)
        if handedOver.remove(ObjectIdentifier(controller)) == nil {
            let saved = controller.state.tabs.filter { AddressResolver.isPageURL($0.url) }.map(\.saved) + controller.state.closed
            primary.state.closed = Array((saved + primary.state.closed).prefix(Session.maxClosed))
        }
        primary.state.scheduleSave()
    }
}
