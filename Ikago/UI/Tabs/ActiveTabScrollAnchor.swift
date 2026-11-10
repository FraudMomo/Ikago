import AppKit
import SwiftUI

/// One native owner reveals clipped active tabs. It never recenters a visible tab.
struct ActiveTabScrollAnchor: FillingViewRepresentable {
    let active: Bool
    func makeNSView(context: Context) -> TabVisibilityAnchor { TabVisibilityAnchor() }
    func updateNSView(_ view: TabVisibilityAnchor, context: Context) {
        let activated = active && !view.active
        view.active = active
        view.scheduleReveal(force: activated)
    }
}

final class TabVisibilityAnchor: NSView {
    var active = false
    private var viewportSize = NSSize.zero
    private var documentSize = NSSize.zero
    private var tabRect = NSRect.zero
    private weak var observedScroll: NSScrollView?
    private let observations = ViewFrameObservations()
    private var scheduled = false
    private var needsForcedReveal = false

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); scheduleReveal(force: true) }
    override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); scheduleReveal(force: true) }
    override func layout() { super.layout(); scheduleReveal() }
    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); scheduleReveal() }
    override func setFrameOrigin(_ newOrigin: NSPoint) { super.setFrameOrigin(newOrigin); scheduleReveal() }

    func scheduleReveal(force: Bool = false) {
        // Only the active tab reveals itself; the others would queue a main-thread block on every frame of motion.
        guard active else { return }
        needsForcedReveal = needsForcedReveal || force
        guard !scheduled else { return }
        scheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.scheduled = false
            self.revealIfNeeded()
        }
    }

    private func revealIfNeeded() {
        guard active, window != nil, let scroll = enclosingScrollView, let document = scroll.documentView else { return }
        if observedScroll !== scroll {
            observations.clear()
            observedScroll = scroll
            scroll.contentView.postsFrameChangedNotifications = true
            document.postsFrameChangedNotifications = true
            for view in [scroll.contentView, document] {
                observations.tokens.append(NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification,
                    object: view, queue: .main) { [weak self] _ in
                        MainActor.assumeIsolated { self?.scheduleReveal() }
                    })
            }
        }
        let viewport = scroll.contentView.bounds.size, size = document.bounds.size
        let rect = document.convert(bounds, from: self)
        guard needsForcedReveal || viewport != viewportSize || size != documentSize || rect != tabRect else { return }
        needsForcedReveal = false
        viewportSize = viewport; documentSize = size; tabRect = rect
        // No proxy centering or animator: only the clipped edge needs to move.
        scrollToVisible(bounds.insetBy(dx: -2, dy: 0))
        scroll.reflectScrolledClipView(scroll.contentView)
    }
}

/// Notification removal is thread safe, including when a SwiftUI view releases its last owner.
private final class ViewFrameObservations: @unchecked Sendable {
    var tokens: [NSObjectProtocol] = []
    func clear() { tokens.forEach { NotificationCenter.default.removeObserver($0) }; tokens = [] }
    deinit { clear() }
}
