import AppKit
import SwiftUI

/// Watches horizontal scroll gestures over the sidebar without becoming an event target.
struct SidebarSpaceSwipe: NSViewRepresentable {
    let state: BrowserState

    func makeNSView(context: Context) -> SidebarSpaceSwipeView {
        let view = SidebarSpaceSwipeView()
        view.state = state
        return view
    }

    func updateNSView(_ view: SidebarSpaceSwipeView, context: Context) { view.state = state }
}

@MainActor
final class SidebarSpaceSwipeView: NSView {
    weak var state: BrowserState?
    private var monitor: Any?
    private var horizontal = false
    private var changedSpace = false
    private var distance: CGFloat = 0

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    isolated deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let window, event.window === window else { return event }
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return event }

        if event.phase.contains(.began) {
            horizontal = false
            changedSpace = false
            distance = 0
        }

        let dx = event.scrollingDeltaX
        let dy = event.scrollingDeltaY
        if !horizontal, abs(dx) > abs(dy) * 1.35, abs(dx) > 0 {
            distance += dx
            if abs(distance) >= 48 { horizontal = true }
        } else if !horizontal {
            distance = 0
        }

        if horizontal {
            if !changedSpace {
                withAnimation(.easeInOut(duration: 0.22)) { state?.selectAdjacentSpace(distance < 0 ? 1 : -1) }
                changedSpace = true
            }
            if event.momentumPhase.contains(.ended) || event.phase.contains(.cancelled) { reset() }
            return nil
        }

        if event.phase.contains(.ended) || event.phase.contains(.cancelled) || event.momentumPhase.contains(.ended) { reset() }
        return event
    }

    private func reset() {
        horizontal = false
        changedSpace = false
        distance = 0
    }
}
