import AppKit
import WebKit
import IKCEFBridge

/// Press and hold just inside the page's top edge (every layout), then drag, to move the
/// window. A local event monitor only watches the mouse, never consumes it: the page gets
/// every press at once, so clicks, selection and scrolling stay immediate, and no view,
/// padding or overlay is added. After a brief `hold` (0.12 s) without moving, the page's press ends
/// away from what was pressed and becomes a native window drag. Double-clicks, modified
/// clicks and presses that move first stay with the page.
@MainActor
final class PageWindowGrab {
    static let edge: CGFloat = 10, hold: TimeInterval = 0.12, slop: CGFloat = 6
    /// Marks Ikago's own page surfaces (internal pages, error and empty pages) as grabbable like web pages.
    static let pageSurface = NSUserInterfaceItemIdentifier("ikago.page-surface")
    private let state: BrowserState
    private weak var content: NSView?
    private var monitor: Any?
    private var press: NSEvent?
    private var timer: Timer?
    /// The real mouse-up that follows a grab; the page already had its release.
    private var swallowsUp = false

    init(content: NSView, state: BrowserState) {
        self.state = state
        self.content = content
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            MainActor.assumeIsolated { self?.observe(event) ?? true } ? event : nil
        }
    }

    /// Ends watching; the window controller calls it when its window closes.
    func stop() {
        cancel()
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    /// Whether the event continues to the page.
    private func observe(_ event: NSEvent) -> Bool {
        switch event.type {
        case .leftMouseDown:
            cancel()
            swallowsUp = false
            guard starts(event) else { return true }
            press = event
            let timer = Timer(timeInterval: Self.hold, repeats: false) { [weak self] _ in MainActor.assumeIsolated { self?.grab() } }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        case .leftMouseDragged:
            guard let press else { return true }
            let a = press.locationInWindow, b = event.locationInWindow
            if hypot(a.x - b.x, a.y - b.y) > Self.slop { cancel() }
        default:
            cancel()
            if swallowsUp { swallowsUp = false; return false }
        }
        return true
    }

    private func cancel() {
        timer?.invalidate()
        timer = nil
        press = nil
    }

    /// A plain single press on the page itself, within `edge` points of the page's top.
    func starts(_ event: NSEvent) -> Bool {
        guard event.clickCount == 1,
              event.modifierFlags.isDisjoint(with: [.command, .shift, .control, .option]),
              let content, let window = content.window, event.window === window,
              let root = window.contentView, let frame = root.superview else { return false }
        let point = content.convert(event.locationInWindow, from: nil)
        let top = content.isFlipped ? point.y : content.bounds.height - point.y
        guard top >= 0, top <= Self.edge, point.x >= 0, point.x <= content.bounds.width else { return false }
        // Split headers, the find bar and other overlays keep their own clicks.
        var view = root.hitTest(frame.convert(event.locationInWindow, from: nil))
        while let current = view, !(current is WKWebView || current is IKCEFPage || current.identifier == Self.pageSurface) { view = current.superview }
        return view != nil
    }

    private func grab() {
        guard let press, let window = press.window, NSEvent.pressedMouseButtons & 1 == 1 else { return cancel() }
        cancel()
        // AppKit routes a mouse-up to the view that took the press, here the page. Releasing it
        // far outside ends the press and any selection without clicking what was pressed (as when
        // a press is released elsewhere); the real release after the drag is dropped.
        if let up = NSEvent.mouseEvent(with: .leftMouseUp, location: NSPoint(x: -10_000, y: -10_000), modifierFlags: [],
                                       timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                       context: nil, eventNumber: press.eventNumber, clickCount: 1, pressure: 0) {
            window.sendEvent(up)
        }
        swallowsUp = true
        // Movable only for the system drag, like `WindowDragArea`.
        let movable = window.isMovable
        window.isMovable = true
        window.performDrag(with: press)
        window.isMovable = movable
    }
}
