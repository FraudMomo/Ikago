import AppKit
import SwiftUI

/// How far the Space's list follows a two-finger swipe, in points. Its own observable, so a swipe redraws only the view
/// that moves (`SpaceSwipeContent`), never the sidebar around it.
@MainActor
@Observable
final class SpaceSwipe {
    var offset: CGFloat = 0
}

/// The part of the sidebar that belongs to the Space (pins and tabs): it follows the fingers while swiping, fading as it
/// goes, and the next Space's list comes in from the other side.
struct SpaceSwipeContent<Content: View>: View {
    let swipe: SpaceSwipe
    let width: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        let progress = min(1, abs(swipe.offset) / max(1, width))
        content
            .offset(x: swipe.offset)
            .opacity(1 - progress * 0.85)
    }
}

/// Watches horizontal scroll gestures over the sidebar without becoming an event target. With a `swipe`, the list
/// follows the fingers and the Space changes when they lift past a third of the way or after a flick, like paging
/// through a horizontal list; otherwise it springs back. Without one (the rail) the Space changes on lift the same way.
struct SidebarSpaceSwipe: NSViewRepresentable {
    let state: BrowserState
    var swipe: SpaceSwipe? = nil

    func makeNSView(context: Context) -> SidebarSpaceSwipeView {
        let view = SidebarSpaceSwipeView()
        view.state = state
        view.swipe = swipe
        return view
    }

    func updateNSView(_ view: SidebarSpaceSwipeView, context: Context) {
        view.state = state
        view.swipe = swipe
    }
}

@MainActor
final class SidebarSpaceSwipeView: NSView {
    weak var state: BrowserState?
    var swipe: SpaceSwipe?
    private var monitor: Any?
    /// The gesture was recognised as horizontal: it belongs to the swipe until its momentum ends.
    private var horizontal = false
    /// The fingers lifted and the swipe was decided; momentum events that follow are swallowed.
    private var settled = false
    private var distance: CGFloat = 0
    private var lastDelta: CGFloat = 0

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
        if event.phase.contains(.began) {
            // A new gesture starts only over the sidebar; one already claimed keeps going wherever the pointer drifts.
            guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return event }
            horizontal = false
            settled = false
            distance = 0
            lastDelta = 0
        }
        // Mice and plain wheels have no phases: leave them to the list.
        guard event.hasPreciseScrollingDeltas else { return event }

        if !horizontal {
            guard event.phase != [], !settled else { return event }
            let dx = event.scrollingDeltaX, dy = event.scrollingDeltaY
            guard abs(dx) > abs(dy) * 1.35, abs(dx) > 0 else { distance = 0; return event }
            distance += dx
            lastDelta = dx
            if abs(distance) >= 10 { horizontal = true; follow(distance) }
            return nil
        }

        if !settled, event.momentumPhase == [] {
            distance += event.scrollingDeltaX
            if event.scrollingDeltaX != 0 { lastDelta = event.scrollingDeltaX }
            follow(distance)
            if event.phase.contains(.ended) { settle(); settled = true }
            if event.phase.contains(.cancelled) { springBack(); settled = true }
        }
        if event.momentumPhase.contains(.ended) || (settled && event.momentumPhase == [] && event.phase.contains(.ended)) {
            horizontal = false
        }
        return nil
    }

    private var width: CGFloat { max(120, bounds.width) }
    private var canSwitch: Bool { (state?.spaces.count ?? 0) > 1 }

    /// The list under the fingers; with one Space it only gives a little, like a list at its end.
    private func follow(_ distance: CGFloat) {
        guard let swipe else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { swipe.offset = canSwitch ? distance : distance * 0.2 }
    }

    private func settle() {
        // Past a third of the sidebar, or a flick in the swipe's direction.
        let flick = abs(lastDelta) > 14 && lastDelta.sign == distance.sign
        guard canSwitch, abs(distance) > width / 3 || flick else { springBack(); return }
        let direction = distance < 0 ? 1 : -1
        guard let swipe, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            swipe?.offset = 0
            state?.selectAdjacentSpace(direction)
            return
        }
        withAnimation(.easeIn(duration: 0.12)) {
            swipe.offset = -CGFloat(direction) * width * 0.55
        } completion: { [weak self] in
            guard let self else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                self.state?.selectAdjacentSpace(direction)
                swipe.offset = CGFloat(direction) * self.width * 0.45
            }
            withAnimation(.spring(duration: 0.32, bounce: 0)) { swipe.offset = 0 }
        }
    }

    private func springBack() {
        guard let swipe, swipe.offset != 0 else { return }
        withAnimation(.spring(duration: 0.3, bounce: 0)) { swipe.offset = 0 }
    }
}
