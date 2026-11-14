import AppKit

/// Two-finger swipes Back/Forward across an engine handoff (`EngineHandoff`): neither engine's own gesture knows the
/// parked page of the other engine. Only at the edge of the page's own history, so it never competes with a page's
/// sideways scrolling or WebKit's native gesture (CEF reports no "unconsumed scroll", so swiping within a Chromium
/// page's own history isn't offered). Followed live by an arrow at the page's edge; navigates on release past
/// `threshold`. Events are only watched, never swallowed. Honors the system's "Swipe between pages" setting.
@MainActor
final class HistorySwipe {
    private var monitor: Any?
    private weak var target: TabController?
    private var back = true
    private var distance: CGFloat = 0
    private var tracking = false
    private var decided = false
    private let indicator = SwipeArrowView()
    static let threshold: CGFloat = 110

    init(controllers: @escaping @MainActor (NSEvent) -> TabController?) {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event, find: controllers) }
            return event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        indicator.removeFromSuperview()
    }

    private func handle(_ event: NSEvent, find: (NSEvent) -> TabController?) {
        guard event.hasPreciseScrollingDeltas, NSEvent.isSwipeTrackingFromScrollEventsEnabled else { return }
        if event.phase.contains(.began) {
            reset()
            target = find(event)
            tracking = target != nil
            return
        }
        guard tracking, let target, event.momentumPhase == [] else { return }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            let go = decided && !event.phase.contains(.cancelled) && abs(distance) >= Self.threshold
            if go { back ? target.goBack() : target.goForward() }
            indicator.finish(navigated: go)
            reset()
            return
        }
        let dx = event.scrollingDeltaX, dy = event.scrollingDeltaY
        // Fingers moving right mean Back, whichever way scrolling is set to go.
        let fingersRight = event.isDirectionInvertedFromDevice ? dx : -dx
        if !decided {
            // Only a clearly sideways start is a swipe; anything else is ordinary scrolling for the rest of the gesture.
            guard abs(dx) + abs(dy) > 0 else { return }
            guard abs(dx) > abs(dy) * 2 else { tracking = false; return }
            back = fingersRight > 0
            guard target.swipeNavigates(back: back) else { tracking = false; return }
            decided = true
            indicator.attach(to: target.hostView, back: back)
        }
        distance += back ? fingersRight : -fingersRight
        distance = max(0, distance)
        indicator.progress = min(1, distance / Self.threshold)
    }

    private func reset() {
        tracking = false; decided = false; distance = 0
    }
}

extension TabController {
    /// Whether a swipe crosses an engine handoff here: the page's own history ends, and the other engine's page waits.
    func swipeNavigates(back: Bool) -> Bool {
        guard page != nil else { return false }
        let parked = back ? (handoff.previous != nil || handoff.previousDestination != nil)
            : (handoff.next != nil || handoff.nextDestination != nil)
        let own = back ? handoff.pageCanGoBack : handoff.pageCanGoForward
        return !own && parked
    }
}

/// The arrow that slides in from the page's edge while swiping; it fills once releasing would navigate.
final class SwipeArrowView: NSView {
    private let arrow = NSImageView()
    private var back = true
    private static let size: CGFloat = 40

    var progress: CGFloat = 0 { didSet { update() } }

    override init(frame: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.size, height: Self.size))
        wantsLayer = true
        layer?.cornerRadius = Self.size / 2
        layer?.cornerCurve = .continuous
        arrow.frame = bounds.insetBy(dx: 10, dy: 10)
        arrow.imageScaling = .scaleProportionallyUpOrDown
        addSubview(arrow)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func attach(to host: NSView, back: Bool) {
        self.back = back
        arrow.image = NSImage(systemSymbolName: back ? "chevron.left" : "chevron.right", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .bold))
        host.addSubview(self, positioned: .above, relativeTo: nil)
        alphaValue = 0
        progress = 0
    }

    private func update() {
        guard let host = superview else { return }
        let ready = progress >= 1
        let travel = 20 + 26 * progress
        let x = back ? -Self.size + travel : host.bounds.width - travel
        frame = NSRect(x: x, y: ((host.bounds.height - Self.size) / 2).rounded(), width: Self.size, height: Self.size)
        alphaValue = min(1, progress * 1.6)
        layer?.backgroundColor = (ready ? NSColor.controlAccentColor : NSColor.windowBackgroundColor.withAlphaComponent(0.92)).cgColor
        arrow.contentTintColor = ready ? .white : .labelColor
        layer?.shadowOpacity = 0.18; layer?.shadowRadius = 6; layer?.shadowOffset = .zero
    }

    func finish(navigated: Bool) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = navigated ? 0.18 : 0.14
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.removeFromSuperview() }
        }
    }
}
