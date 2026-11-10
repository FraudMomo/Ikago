import AppKit
import SwiftUI

/// A vertical sidebar list in AppKit's own scroll view, like Finder's and Mail's sidebars.
///
/// The rows live in their own `NSHostingView`, the scroll view's document. Scrolling then moves that view the native
/// way, through the clip view: SwiftUI does no work per scroll frame, and fast trackpad flicks and momentum behave
/// exactly like any Mac list. It also keeps the list's view graph apart from the window's, so a change elsewhere in the
/// window doesn't walk every row, and a change in a row doesn't walk the window.
///
/// While the list scrolls, rows ignore hover (`sidebarHover`), so a resting pointer doesn't flip each row it passes.
struct SidebarScrollView<Content: View>: View {
    /// Kept for callers; drags work natively, so the list no longer needs to know about them.
    var chrome: ChromeModel? = nil
    @ViewBuilder let content: Content

    var body: some View {
        NativeScrollView(content: content)
    }
}

private struct NativeScrollView<Content: View>: FillingViewRepresentable {
    let content: Content
    @Environment(\.self) private var environment

    @MainActor final class Coordinator {
        let activity = ScrollActivity()
        let report = HeightReport()
        var observers: [NSObjectProtocol] = []
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> ListScrollView {
        let scrollView = ListScrollView()
        let host = ListHostingView(rootView: root(context))
        scrollView.documentView = host
        context.coordinator.report.changed = { [weak scrollView] height in scrollView?.setContentHeight(height) }

        let activity = context.coordinator.activity
        let center = NotificationCenter.default
        context.coordinator.observers = [
            center.addObserver(forName: NSScrollView.willStartLiveScrollNotification, object: scrollView, queue: .main) { [weak scrollView] _ in
                MainActor.assumeIsolated {
                    if !activity.scrolling { activity.scrolling = true }
                    scrollView?.setLiveScrolling(true)
                }
            },
            center.addObserver(forName: NSScrollView.didEndLiveScrollNotification, object: scrollView, queue: .main) { [weak scrollView] _ in
                MainActor.assumeIsolated {
                    if activity.scrolling { activity.scrolling = false }
                    scrollView?.setLiveScrolling(false)
                }
            },
        ]
        return scrollView
    }

    static func dismantleNSView(_ scrollView: ListScrollView, coordinator: Coordinator) {
        coordinator.observers.forEach(NotificationCenter.default.removeObserver)
        coordinator.observers = []
    }

    func updateNSView(_ scrollView: ListScrollView, context: Context) {
        // The rows live in another view graph: hand the update over with its transaction, or a `withAnimation` in the
        // sidebar would animate only what happens to observe the model, and the rest would jump a frame later.
        let host = scrollView.documentView as? ListHostingView<ScrollRoot<Content>>
        withTransaction(context.transaction) { host?.rootView = root(context) }
    }

    private func root(_ context: Context) -> ScrollRoot<Content> {
        ScrollRoot(content: content, activity: context.coordinator.activity, environment: environment,
                   report: context.coordinator.report)
    }
}

/// The list's scroll view: no scroller, native momentum and bounce, and the document sized by hand.
///
/// The document is exactly as wide as the list and as tall as its content (at least the visible height), set only when
/// that changes. The height is the one SwiftUI measures for the rows themselves (`ScrollRoot`): the host's own
/// intrinsic size didn't shrink when a group collapsed, which left empty space to scroll into.
/// Edges with content beyond them fade out instead of cutting hard.
final class ListScrollView: NSScrollView {
    private let fade = CAGradientLayer()
    private static let fadeLength: CGFloat = 18

    override init(frame: NSRect) {
        super.init(frame: frame)
        drawsBackground = false
        contentView.drawsBackground = false
        hasVerticalScroller = false
        hasHorizontalScroller = false
        verticalScrollElasticity = .allowed
        horizontalScrollElasticity = .none
        wantsLayer = true
        fade.colors = [NSColor.clear.cgColor, NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    /// When a trackpad or wheel scroll (with its momentum) began; nil otherwise.
    private var liveScrollStart: Date?

    /// The rows are already drawn into layers for the whole document, so scrolling only has to move them. SwiftUI
    /// would still re-render the list on every scroll step, because its position in the window changed: measured at
    /// a third of the main thread with 100 tabs, growing with the number of tabs. While a scroll is live the rows'
    /// host skips those passes (after a moment, so rows can drop their hover), and catches up when it ends.
    var pausesRowUpdates: Bool { liveScrollStart.map { Date().timeIntervalSince($0) > 0.05 } ?? false }

    func setLiveScrolling(_ scrolling: Bool) {
        if scrolling { stopFollowing() }
        liveScrollStart = scrolling ? (liveScrollStart ?? Date()) : nil
        if !scrolling { documentView?.needsLayout = true }
    }

    /// True while this view lays out, so the host's size change it causes doesn't ask for another pass.
    private(set) var isLayingOut = false

    override func layout() {
        isLayingOut = true
        defer { isLayingOut = false }
        super.layout()
        sizeDocument()
        updateFade()
    }

    override func reflectScrolledClipView(_ clipView: NSClipView) {
        super.reflectScrolledClipView(clipView)
        updateFade()
    }

    private var contentHeight: CGFloat = 0
    private var shrink: DispatchWorkItem?
    /// Rows that leave (a group closing) animate out first; the document gives up their space afterwards, once the
    /// list has finished following them (`follow`).
    private static let shrinkDelay = Animation.groupDisclosureDuration * 1.8

    /// The rows' measured height (SwiftUI reports the final one at once, not the animated ones). A taller list gets
    /// its room at once. A shorter one keeps it until the rows have animated away; if the list was scrolled past its
    /// new end, it scrolls there along with the closing rows, so the bottom of the list stays put like Finder's.
    func setContentHeight(_ height: CGFloat) {
        let height = height.rounded(.up)
        guard height != contentHeight else { return }
        let shrinks = height < contentHeight
        contentHeight = height
        shrink?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.applyContentHeight(animated: shrinks) }
        shrink = work
        if shrinks {
            let visible = contentView.bounds
            let lowest = max(0, max(visible.height, height) - visible.height)
            if visible.minY > lowest + 0.5 { follow(to: lowest) }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.shrinkDelay, execute: work)
        }
        // Never inside a layout pass: resizing the document there asks AppKit for another one.
        else if isLayingOut { DispatchQueue.main.async(execute: work) }
        else { work.perform() }
    }

    private func applyContentHeight(animated: Bool) {
        let visible = contentView.bounds
        let lowest = max(0, max(visible.height, contentHeight) - visible.height)
        guard animated, following == nil, visible.minY > lowest, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            if following == nil {
                sizeDocument()
                updateFade()
            }
            return
        }
        // Still scrolled past the new end (the user scrolled meanwhile): glide there, then give up the space.
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            contentView.animator().setBoundsOrigin(NSPoint(x: visible.minX, y: lowest))
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                self?.sizeDocument()
                self?.updateFade()
            }
        })
    }

    // MARK: Following a closing group

    private var following: CADisplayLink?
    private var followFrom: CGFloat = 0
    private var followTo: CGFloat = 0
    private var followStart: CFTimeInterval = 0

    /// Scrolls to `y` on the same critically damped spring as `Animation.groupDisclosure`, frame by frame, so the
    /// scroll and the rows SwiftUI animates move as one. Measured: a delayed glide afterwards left the list still for
    /// 0.3 s with empty space at its end, then moved everything.
    private func follow(to y: CGFloat) {
        stopFollowing()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            contentView.scroll(to: NSPoint(x: contentView.bounds.minX, y: y))
            reflectScrolledClipView(contentView)
            return
        }
        followFrom = contentView.bounds.minY
        followTo = y
        followStart = CACurrentMediaTime()
        let link = displayLink(target: self, selector: #selector(followStep(_:)))
        link.add(to: .main, forMode: .common)
        following = link
    }

    @objc private func followStep(_ link: CADisplayLink) {
        let t = max(0, link.targetTimestamp - followStart)
        let duration = Animation.groupDisclosureDuration
        // SwiftUI's `smooth(duration:)` is a spring with no bounce: x(t) = 1 − (1 + ωt)·e^(−ωt), ω = 2π / duration.
        let omega = 2 * Double.pi / duration
        let done = t >= duration * 1.6
        let progress = done ? 1 : 1 - (1 + omega * t) * exp(-omega * t)
        contentView.scroll(to: NSPoint(x: contentView.bounds.minX, y: followFrom + (followTo - followFrom) * progress))
        reflectScrolledClipView(contentView)
        if done { stopFollowing() }
    }

    private func stopFollowing() {
        following?.invalidate()
        following = nil
    }

    private func sizeDocument() {
        guard let document = documentView else { return }
        let visible = contentView.bounds
        let size = NSSize(width: visible.width, height: max(visible.height, contentHeight))
        guard document.frame.size != size else { return }
        document.setFrameSize(size)
        // A shorter list must not stay scrolled past its new end.
        let lowest = max(0, size.height - visible.height)
        if visible.minY > lowest {
            contentView.scroll(to: NSPoint(x: visible.minX, y: lowest))
            reflectScrolledClipView(contentView)
        }
    }

    private func updateFade() {
        guard let layer, let document = documentView else { return }
        let visible = contentView.bounds
        let height = max(1, bounds.height)
        let top = visible.minY > 0.5, bottom = visible.maxY < document.frame.height - 0.5
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if top || bottom {
            let edge = min(0.4, Self.fadeLength / height)
            fade.frame = layer.bounds
            // Inside SwiftUI the scroll view's layer is flipped (measured), so the first color stop is the top edge;
            // otherwise it is the bottom edge.
            let (first, last) = layer.contentsAreFlipped() ? (top, bottom) : (bottom, top)
            fade.locations = [0, NSNumber(value: first ? edge : 0), NSNumber(value: last ? 1 - edge : 1), 1]
            if layer.mask !== fade { layer.mask = fade }
        } else if layer.mask != nil {
            layer.mask = nil
        }
        CATransaction.commit()
    }
}

/// Carries the rows' measured height from SwiftUI to the scroll view.
@MainActor
final class HeightReport {
    var changed: ((CGFloat) -> Void)?
}

@MainActor @Observable
private final class ScrollActivity {
    var scrolling = false
}

/// The list's own root: the window's environment carried across, plus whether the list is scrolling.
private struct ScrollRoot<Content: View>: View {
    let content: Content
    let activity: ScrollActivity
    let environment: EnvironmentValues
    let report: HeightReport

    var body: some View {
        // Several views stack, as they did in a SwiftUI scroll view.
        VStack(spacing: 0) { content }
            // The rows at their own height, whatever the document's is: this is the height the document follows.
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { report.changed?($0) }
            .environment(\.self, environment)
            .environment(\.sidebarScrolling, activity.scrolling)
            // `minHeight: 0` makes the frame take the document's size even while the rows are taller (a group just
            // opened, the document not grown yet). Without it the frame grows with the rows and the host centers it,
            // which moved the whole list up by half the new height for a frame.
            .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
            .frame(maxWidth: .infinity)
    }
}
