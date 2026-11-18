import AppKit
import IKCEFBridge
import SwiftUI
import WebKit

/// How far the Space's list follows a two-finger swipe, in points. Its own observable, so a swipe redraws only the view
/// that moves (`SpaceSwipeContent`), never the sidebar around it.
@MainActor
@Observable
final class SpaceSwipe {
    var offset: CGFloat = 0

    /// How far the list travels before it has faded out completely, as a share of the sidebar's width. The outgoing
    /// Space leaves to this point and the incoming one starts from the mirrored point, both invisible there, so the
    /// moment the Spaces swap never shows.
    static let fadeSpan: CGFloat = 0.5

    /// The list's opacity at `offset`: fully drawn at rest, gone at `fadeSpan`. Eased, so small drags barely dim it and
    /// the fade picks up as the swipe commits.
    static func opacity(offset: CGFloat, width: CGFloat) -> Double {
        let t = min(1, abs(offset) / max(1, width * fadeSpan))
        return Double(1 - t * t * (3 - 2 * t))
    }
}

/// The part of the sidebar that belongs to the Space (pins and tabs): it follows the fingers while swiping, fading as it
/// goes, and the next Space's list comes in from the other side.
struct SpaceSwipeContent<Content: View>: View {
    let swipe: SpaceSwipe
    let width: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        content
            .offset(x: swipe.offset)
            .opacity(SpaceSwipe.opacity(offset: swipe.offset, width: width))
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
    /// Recent finger positions (time, distance) for the release speed.
    private var samples: [(time: TimeInterval, distance: CGFloat)] = []
    /// A release animation is running; gestures that start meanwhile are left to the list.
    private var animating = false
    /// The current gesture began over this sidebar; every other gesture (a page's own sideways swipe) is left alone.
    private var tracking = false

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
            horizontal = false
            settled = false
            distance = 0
            samples = []
            tracking = !animating && startsHere(event)
        }
        // Mice and plain wheels have no phases: leave them to the list.
        guard tracking, event.hasPreciseScrollingDeltas else { return event }

        if !horizontal {
            guard event.phase != [], !settled else { return event }
            let dx = event.scrollingDeltaX, dy = event.scrollingDeltaY
            guard abs(dx) > abs(dy) * 1.35, abs(dx) > 0 else { distance = 0; samples = []; return event }
            distance += dx
            record(event)
            if abs(distance) >= 10 { horizontal = true; follow(distance) }
            return nil
        }

        if !settled, event.momentumPhase == [] {
            distance += event.scrollingDeltaX
            record(event)
            follow(distance)
            if event.phase.contains(.ended) { settle(); settled = true }
            if event.phase.contains(.cancelled) { springBack(velocity: 0); settled = true }
        }
        if event.momentumPhase.contains(.ended) || (settled && event.momentumPhase == [] && event.phase.contains(.ended)) {
            horizontal = false
        }
        return nil
    }

    private func record(_ event: NSEvent) {
        samples.append((event.timestamp, distance))
        samples.removeAll { event.timestamp - $0.time > 0.08 }
    }

    /// The fingers' speed over the last few events, in points per second (0 when they had stopped before lifting).
    private var velocity: CGFloat {
        guard let first = samples.first, let last = samples.last, last.time - first.time > 0.004 else { return 0 }
        return (last.distance - first.distance) / CGFloat(last.time - first.time)
    }

    /// Over this sidebar while it is on screen, and not over a page drawn above it (a hidden sidebar's page, a peek).
    private func startsHere(_ event: NSEvent) -> Bool {
        guard !isHiddenOrHasHiddenAncestor, alphaValue > 0, let window,
              bounds.contains(convert(event.locationInWindow, from: nil)) else { return false }
        var view = window.contentView?.superview?.hitTest(event.locationInWindow) ?? window.contentView?.hitTest(event.locationInWindow)
        while let current = view {
            if current is WKWebView || current is IKCEFPage { return false }
            view = current.superview
        }
        return true
    }

    private var width: CGFloat { max(120, bounds.width) }
    private var canSwitch: Bool { (state?.spaces.count ?? 0) > 1 }

    /// The list under the fingers, point for point; with one Space it only gives a little, like a list at its end.
    private func follow(_ distance: CGFloat) {
        guard let swipe else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { swipe.offset = canSwitch ? distance : distance * 0.2 }
    }

    /// Decides on lift: past a third of the sidebar, or a flick that way, pages to the next Space; a flick back, or a
    /// short drag, springs back. The animation carries on at the fingers' speed, so the list never jumps or stalls.
    private func settle() {
        let speed = velocity
        let flickForward = abs(speed) > 300 && speed.sign == distance.sign
        let flickBack = abs(speed) > 300 && speed.sign != distance.sign
        guard canSwitch, (abs(distance) > width / 3 && !flickBack) || flickForward else {
            springBack(velocity: speed); return
        }
        let direction = distance < 0 ? 1 : -1
        guard let swipe, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            swipe?.offset = 0
            state?.selectAdjacentSpace(direction)
            return
        }
        // Out: from where the fingers left it to where it has faded away, no slower than they were moving.
        let edge = width * SpaceSwipe.fadeSpan
        let exit = -CGFloat(direction) * max(edge, abs(swipe.offset))
        let remaining = abs(exit - swipe.offset)
        let outSpeed = max(abs(speed), 900)
        let outDuration = remaining < 1 ? 0 : min(0.18, max(0.06, Double(remaining / outSpeed)))
        animating = true
        withAnimation(.linear(duration: outDuration)) {
            swipe.offset = exit
        } completion: { [weak self] in
            guard let self else { return }
            // Swap while both lists are invisible, then bring the new one in from the mirrored point, starting at the
            // speed the old one left with.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                self.state?.selectAdjacentSpace(direction)
                swipe.offset = CGFloat(direction) * edge
            }
            let initial = Double(min(4, outSpeed / max(1, edge)))
            withAnimation(.interpolatingSpring(.init(duration: 0.34, bounce: 0), initialVelocity: initial)) {
                swipe.offset = 0
            } completion: { [weak self] in
                self?.animating = false
            }
        }
    }

    /// Back to rest, starting at the fingers' speed when they were already heading home.
    private func springBack(velocity: CGFloat) {
        guard let swipe, swipe.offset != 0 else { return }
        let toward = -velocity * (swipe.offset < 0 ? -1 : 1)  // positive: moving home
        let initial = Double(max(0, min(6, toward / max(1, abs(swipe.offset)))))
        animating = true
        withAnimation(.interpolatingSpring(.init(duration: 0.3, bounce: 0), initialVelocity: initial)) {
            swipe.offset = 0
        } completion: { [weak self] in
            self?.animating = false
        }
    }
}
