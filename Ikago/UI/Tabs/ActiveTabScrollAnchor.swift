import AppKit
import SwiftUI

/// Geometry preferences exist even when SwiftUI has culled an offscreen AppKit field.
/// One native owner on the viewport reveals the active slot before the editor mounts.
struct ActiveTabScrollAnchor: View {
    let active: Bool
    var body: some View {
        GeometryReader { geometry in
            if active {
                Color.clear.preference(key: ActiveTabBoundsKey.self,
                    value: geometry.frame(in: .named("ikago-tab-document")))
            }
        }.allowsHitTesting(false)
    }
}

private struct ActiveTabBoundsKey: PreferenceKey {
    static let defaultValue: CGRect? = nil
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) { value = nextValue() ?? value }
}

extension View {
    func revealActiveTab() -> some View {
        overlayPreferenceValue(ActiveTabBoundsKey.self) { rect in
            TabViewportReveal(target: rect).allowsHitTesting(false)
        }
    }
}

private struct TabViewportReveal: FillingViewRepresentable {
    let target: CGRect?
    func makeNSView(context: Context) -> TabVisibilityAnchor { TabVisibilityAnchor() }
    func updateNSView(_ view: TabVisibilityAnchor, context: Context) {
        guard view.target != target else { return }
        view.target = target
        view.scheduleReveal()
    }
}

final class TabVisibilityAnchor: NSView {
    var target: CGRect?
    private weak var scroll: NSScrollView?
    private let observations = ViewFrameObservations()
    private var scheduled = false

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); scheduleReveal() }
    override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); scheduleReveal() }
    override func layout() { super.layout(); scheduleReveal() }

    func scheduleReveal() {
        guard !scheduled, target != nil else { return }
        scheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.scheduled = false
            self.revealIfNeeded()
        }
    }

    private func findScrollView() -> NSScrollView? {
        guard let window else { return nil }
        let own = convert(bounds, to: window.contentView)
        func find(_ view: NSView) -> NSScrollView? {
            if let candidate = view as? NSScrollView {
                let frame = candidate.convert(candidate.bounds, to: window.contentView)
                if abs(frame.width - own.width) < 4, abs(frame.midX - own.midX) < 4,
                   frame.intersects(own) { return candidate }
            }
            return view.subviews.lazy.compactMap(find).first
        }
        var ancestor = superview
        for _ in 0..<10 {
            guard let view = ancestor else { return nil }
            if let match = find(view) { return match }
            ancestor = view.superview
        }
        return nil
    }

    private func revealIfNeeded() {
        guard window != nil, let target, target.width > 0 else { return }
        if scroll?.window !== window { scroll = nil }
        if scroll == nil, let found = findScrollView(), let document = found.documentView {
            scroll = found
            observations.clear()
            for view in [found.contentView, document] {
                view.postsFrameChangedNotifications = true
                observations.tokens.append(NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification,
                    object: view, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.scheduleReveal() } })
            }
        }
        guard let scroll, let document = scroll.documentView else { return }
        let visible = scroll.contentView.bounds
        var x = visible.minX
        if target.minX < visible.minX { x = target.minX - 2 }
        else if target.maxX > visible.maxX { x = target.maxX - visible.width + 2 }
        x = min(max(0, document.bounds.width - visible.width), max(0, x))
        guard abs(x - visible.minX) > 0.5 else { return }
        // Reveal a clipped edge immediately; never recenter an already visible tab.
        scroll.contentView.scroll(to: NSPoint(x: x, y: visible.minY))
        scroll.reflectScrolledClipView(scroll.contentView)
    }
}

private final class ViewFrameObservations: @unchecked Sendable {
    var tokens: [NSObjectProtocol] = []
    func clear() { tokens.forEach { NotificationCenter.default.removeObserver($0) }; tokens = [] }
    deinit { clear() }
}
