import AppKit
import SwiftUI

/// The small header that drops down from the page's top edge while the pointer rests there (`PageGrabMode.header`).
/// Dragging it moves the window like a title bar (edge tiling and snapping included); a double-click zooms the window
/// when `pageGrabZoom` allows. It appears under the pointer, slides back up once the pointer leaves, and lives in the
/// pages' container above every page, so no page is moved or resized.
@MainActor
final class PageGrabHeader: NSView {
    static let size = CGSize(width: 168, height: 26)
    /// How long the pointer rests on the edge before the header drops, and lingers after leaving before it goes.
    static let dwell: TimeInterval = 0.18, linger: TimeInterval = 0.45
    private let state: BrowserState
    private var dwellTimer: Timer?
    private var lingerTimer: Timer?
    private var pointer: CGFloat = 0
    private(set) var isShown = false

    init(state: BrowserState) {
        self.state = state
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        wantsLayer = true
        let look = NSHostingView(rootView: PageGrabHeaderLook(state: state))
        look.sizingOptions = []
        look.safeAreaRegions = []
        look.frame = bounds
        look.autoresizingMask = [.width, .height]
        addSubview(look)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    // The whole header is the handle: its SwiftUI look never takes the click.
    override func hitTest(_ point: NSPoint) -> NSView? { isShown && frame.contains(point) ? self : nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// The pointer moved over the window; `onEdge` says whether it rests on a page's top edge.
    func pointerMoved(onEdge: Bool, at point: NSPoint, in content: NSView) {
        if isShown {
            guard !frame.contains(point) else { lingerTimer?.invalidate(); return }
            if !onEdge { scheduleHide() }
            return
        }
        guard onEdge else { dwellTimer?.invalidate(); dwellTimer = nil; return }
        pointer = point.x
        guard dwellTimer == nil else { return }
        let timer = Timer(timeInterval: Self.dwell, repeats: false) { [weak self, weak content] _ in
            MainActor.assumeIsolated {
                self?.dwellTimer = nil
                if let content { self?.show(in: content) }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        dwellTimer = timer
    }

    func show(in content: NSView, at x: CGFloat? = nil) {
        if let x { pointer = x }
        lingerTimer?.invalidate()
        let margin = Radius.card + 4, width = min(Self.size.width, content.bounds.width - 2 * margin)
        guard width > 40 else { return }
        let x = (pointer - width / 2).clamped(to: margin...(content.bounds.width - margin - width))
        let top = content.isFlipped ? 0 : content.bounds.height - Self.size.height
        let rest = NSRect(x: x, y: top, width: width, height: Self.size.height)
        let raised = rest.offsetBy(dx: 0, dy: content.isFlipped ? -Self.size.height : Self.size.height)
        autoresizingMask = content.isFlipped ? [.maxYMargin] : [.minYMargin]
        // Above every page, including ones added since it last showed.
        content.addSubview(self, positioned: .above, relativeTo: nil)
        isShown = true
        let still = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        frame = still ? rest : raised
        alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().frame = rest
            animator().alphaValue = 1
        }
    }

    func hide(animated: Bool = true) {
        dwellTimer?.invalidate(); dwellTimer = nil
        lingerTimer?.invalidate(); lingerTimer = nil
        guard isShown, let content = superview else { return }
        isShown = false
        guard animated else { return removeFromSuperview() }
        let still = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let raised = frame.offsetBy(dx: 0, dy: content.isFlipped ? -frame.height : frame.height)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            if !still { animator().frame = raised }
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated { if self?.isShown == false { self?.removeFromSuperview() } }
        }
    }

    private func scheduleHide() {
        guard lingerTimer == nil || lingerTimer?.isValid == false else { return }
        let timer = Timer(timeInterval: Self.linger, repeats: false) { [weak self] _ in MainActor.assumeIsolated { self?.hide() } }
        RunLoop.main.add(timer, forMode: .common)
        lingerTimer = timer
    }

    override func mouseEntered(with event: NSEvent) { lingerTimer?.invalidate() }
    override func mouseExited(with event: NSEvent) { scheduleHide() }

    // The window is not movable (see BrowserWindowController); it is just for the system drag, as in `WindowDragArea`.
    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        lingerTimer?.invalidate()
        if event.clickCount == 2 {
            if state.browserPreferences.pageGrabZoom ?? true { window.zoom(nil) }
            return hide()
        }
        let movable = window.isMovable
        window.isMovable = true
        window.performDrag(with: event)
        window.isMovable = movable
        // The drag ends with the release; the header goes unless the pointer is still on it.
        if let superview, !frame.contains(superview.convert(window.mouseLocationOutsideOfEventStream, from: nil)) { scheduleHide() }
    }
}

/// The header's look: a glass tab with a grabber, square where it meets the page's top.
private struct PageGrabHeaderLook: View {
    let state: BrowserState

    var body: some View {
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: Radius.row, bottomTrailingRadius: Radius.row)
        Capsule()
            .fill(state.palette.secondary)
            .frame(width: 34, height: 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .surface(shape, state.palette)
            .contentShape(shape)
            .help("Drag to move the window")
    }
}
