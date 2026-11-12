import AppKit
import SwiftUI

/// Observe native scrolling without injecting a listener into every page.
struct BarScrollBehavior: FillingViewRepresentable {
    let state: BrowserState
    let chrome: ChromeModel
    func makeNSView(context: Context) -> BarScrollObserver {
        let view = BarScrollObserver()
        view.state = state; view.chrome = chrome
        return view
    }
    func updateNSView(_ view: BarScrollObserver, context: Context) { view.state = state; view.chrome = chrome }
}

final class BarScrollObserver: NSView {
    weak var state: BrowserState?
    weak var chrome: ChromeModel?
    private var monitor: Any?
    private var distance: CGFloat = 0
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.observe(event)
            return event
        }
    }
    isolated deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    private func observe(_ event: NSEvent) {
        guard event.window === window, let state, state.tabLayout.usesTopTabs,
              state.browserPreferences.collapseBarOnScroll == true, !state.isImmersive,
              chrome?.holdsPeek != true, chrome?.showTabOverview != true,
              abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) else { return }
        let point = convert(event.locationInWindow, from: nil)
        let fromTop = isFlipped ? point.y : bounds.height - point.y
        guard state.barAtBottom ? fromTop < bounds.height - state.topBarHeaderHeight : fromTop > state.topBarHeaderHeight else { return }
        let delta = event.scrollingDeltaY
        if (delta > 0) != (distance > 0) { distance = 0 }
        distance += delta
        if distance < -80 { withAnimation(.easeInOut(duration: 0.22)) { state.barCondensed = true }; distance = 0 }
        if distance > 28 { withAnimation(.easeInOut(duration: 0.22)) { state.barCondensed = false }; distance = 0 }
    }
}
