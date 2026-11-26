import AppKit
import SwiftUI

/// Traffic lights Ikago draws itself where the system's can't go: in full screen (`BrowserWindowController+FullScreen`),
/// below the band and the menu bar, and in a column at the top of the sidebar's icon rail (`SidebarRail`). The
/// system buttons are hidden meanwhile. Close closes the window, minimize minimizes it, and zoom toggles full
/// screen. The buttons sit just above the shell and below a page lifted for
/// video fullscreen.
@MainActor
final class FullScreenWindowControls {
    private weak var window: NSWindow?
    private let model = FullScreenControlsModel()
    private var host: LightsHost?
    /// The windowed traffic lights, measured from the content view's top-left, for layouts that leave
    /// them where AppKit puts them (Sidebar).
    private var measured: (firstX: CGFloat, centerFromTop: CGFloat, spacing: CGFloat, size: CGFloat)?

    init(window: NSWindow) { self.window = window }

    var isShown: Bool { host != nil }
    var hostView: NSView? { host }
    var debugFrame: String { host.map { "frame=\($0.frame) hidden=\($0.isHidden) alpha=\($0.alphaValue)" } ?? "none" }

    /// Before the window changes: remember where the windowed buttons are.
    func measure() {
        guard let window, let content = window.contentView,
              let close = window.standardWindowButton(.closeButton), let zoom = window.standardWindowButton(.zoomButton),
              let parent = close.superview, close.window === window else { return }
        let a = content.convert(close.frame, from: parent), b = content.convert(zoom.frame, from: zoom.superview)
        let top = content.isFlipped ? a.midY - content.bounds.minY : content.bounds.maxY - a.midY
        measured = (a.minX, top, (b.minX - a.minX) / 2, a.width)
    }

    /// Just above `shell`, so a page lifted for video fullscreen stays on top. Never relative to the first subview:
    /// with the frosted window that is the window's material, and the whole shell covered the buttons.
    func show(above shell: NSView?) {
        guard let window, let content = window.contentView else { return }
        let host = self.host ?? LightsHost(rootView: FullScreenControlsView(model: model, window: window), model: model)
        host.sizingOptions = []
        host.safeAreaRegions = []
        let anchor = shell?.superview === content ? shell : content.subviews.last { !($0 is LightsHost) }
        let subviews = content.subviews
        if let anchor, let at = subviews.firstIndex(of: anchor), subviews.firstIndex(of: host) == at + 1 {} else {
            content.addSubview(host, positioned: .above, relativeTo: anchor)
        }
        self.host = host
    }

    func hide() {
        host?.removeFromSuperview()
        host = nil
    }

    /// Same place as the windowed buttons: `firstX`/`centerFromTop` when a layout positions them, otherwise
    /// where AppKit had them.
    /// `firstX` is the first button's left edge, `centerFromTop` its centre; `vertical` stacks them downwards.
    func place(firstX: CGFloat?, centerFromTop: CGFloat?, band: CGFloat, vertical: Bool = false, visible: Bool) {
        guard let host, let content = host.superview else { return }
        let size = measured?.size ?? 14, spacing = measured?.spacing ?? 23
        let x = firstX ?? measured?.firstX ?? 19
        let center = band + (centerFromTop ?? measured?.centerFromTop ?? 26)
        model.size = size; model.spacing = spacing; model.vertical = vertical
        model.travel = nil
        let long = size + spacing * 2
        let width = vertical ? size : long, height = vertical ? long : size
        let firstCenterOffset = vertical ? height - size / 2 : height / 2
        let y = content.isFlipped ? content.bounds.minY + center - size / 2 : content.bounds.maxY - center - firstCenterOffset
        let frame = NSRect(x: x, y: y, width: width, height: height).integral
        if host.frame != frame { host.frame = frame }
        host.autoresizingMask = content.isFlipped ? [.maxXMargin, .maxYMargin] : [.maxXMargin, .minYMargin]
        // In with the revealed bar (a short fade after it starts moving), out at once with it.
        if visible, host.isHidden || host.alphaValue < 1 {
            host.isHidden = false
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                host.animator().alphaValue = 1
            }
        } else if !visible {
            host.alphaValue = 0
            host.isHidden = true
        }
    }
}

extension FullScreenWindowControls {
    /// The icon rail's lights: a column in the rail, or, while Expand's full sidebar is out over it, a row in its top
    /// row. The host covers both places and each light glides between them on Expand's own curves, so the lights travel
    /// with the panel instead of jumping. `column`/`row` are the first light's left edge and centre from the top.
    func placeRail(column: (x: CGFloat, centerFromTop: CGFloat), row: (x: CGFloat, centerFromTop: CGFloat), band: CGFloat,
                   expanded: Bool) {
        guard let host, let content = host.superview else { return }
        let size = measuredSize, spacing = measuredSpacing
        let long = size + spacing * 2
        // Both layouts in content coordinates from the top: the column's and the row's top-left corners.
        let columnTop = CGPoint(x: column.x, y: band + column.centerFromTop - size / 2)
        let rowTop = CGPoint(x: row.x, y: band + row.centerFromTop - size / 2)
        let minX = min(columnTop.x, rowTop.x), minY = min(columnTop.y, rowTop.y)
        let maxX = max(columnTop.x + size, rowTop.x + long), maxY = max(columnTop.y + long, rowTop.y + size)
        let y = content.isFlipped ? content.bounds.minY + minY : content.bounds.maxY - maxY
        let frame = NSRect(x: minX, y: y, width: maxX - minX, height: maxY - minY).integral
        if host.frame != frame { host.frame = frame }
        host.autoresizingMask = content.isFlipped ? [.maxXMargin, .maxYMargin] : [.maxXMargin, .minYMargin]
        let travel = FullScreenControlsModel.Travel(column: CGPoint(x: columnTop.x - frame.minX, y: columnTop.y - minY),
                                                    row: CGPoint(x: rowTop.x - frame.minX, y: rowTop.y - minY))
        let first = model.travel == nil || model.size != size || model.spacing != spacing
        model.size = size; model.spacing = spacing; model.vertical = false
        if first || model.travel != travel {
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction) { model.travel = travel; if first { model.progress = expanded ? 1 : 0 } }
        }
        let target: CGFloat = expanded ? 1 : 0
        if model.progress != target { withAnimation(expanded ? RailHover.reveal : RailHover.conceal) { model.progress = target } }
        model.target = target
        if host.isHidden || host.alphaValue < 1 { host.isHidden = false; host.alphaValue = 1 }
    }

    /// The three lights where they are headed (window coordinates), for the Expand panel's holes and click-through.
    func lightRects(in window: NSWindow) -> [CGRect] {
        guard let host, host.window === window, !host.isHidden, host.alphaValue > 0 else { return [] }
        return model.rects(progress: model.target).map { host.convert($0, to: nil) }
    }

    private var measuredSize: CGFloat { measured?.size ?? 14 }
    private var measuredSpacing: CGFloat { measured?.spacing ?? 23 }
}

/// Takes clicks only on the lights themselves: the host is larger than them while they travel between the rail's
/// column and Expand's row.
private final class LightsHost: NSHostingView<FullScreenControlsView> {
    let model: FullScreenControlsModel
    init(rootView: FullScreenControlsView, model: FullScreenControlsModel) {
        self.model = model
        super.init(rootView: rootView)
    }
    @MainActor required init(rootView: FullScreenControlsView) { fatalError("init(rootView:) is not used") }
    @MainActor @preconcurrency required dynamic init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard model.travel != nil else { return super.hitTest(point) }
        let local = convert(point, from: superview)
        let rects = model.rects(progress: model.progress).map { $0.insetBy(dx: -2, dy: -2) }
        return rects.contains { $0.contains(local) } ? super.hitTest(point) : nil
    }
}

@MainActor
@Observable
final class FullScreenControlsModel {
    var size: CGFloat = 14
    var spacing: CGFloat = 23
    var vertical = false
    /// The rail's lights: their column and row places in the host (top-left of the first light, from the host's
    /// top-left), and how far along they are (0 column, 1 row). Nil when the lights are simply a row or a column.
    struct Travel: Equatable { var column: CGPoint; var row: CGPoint }
    var travel: Travel?
    var progress: CGFloat = 0
    @ObservationIgnored var target: CGFloat = 0

    /// Each light's frame in the host (AppKit coordinates of an unflipped host are converted by the caller) at `progress`.
    func offset(_ index: Int, progress: CGFloat) -> CGPoint {
        guard let travel else {
            return vertical ? CGPoint(x: 0, y: CGFloat(index) * spacing) : CGPoint(x: CGFloat(index) * spacing, y: 0)
        }
        let a = CGPoint(x: travel.column.x, y: travel.column.y + CGFloat(index) * spacing)
        let b = CGPoint(x: travel.row.x + CGFloat(index) * spacing, y: travel.row.y)
        return CGPoint(x: a.x + (b.x - a.x) * progress, y: a.y + (b.y - a.y) * progress)
    }

    /// The lights' frames in host coordinates (from the top-left, as SwiftUI lays them out; the host is flipped).
    func rects(progress: CGFloat) -> [CGRect] {
        (0..<3).map { let p = offset($0, progress: progress); return CGRect(x: p.x, y: p.y, width: size, height: size) }
    }
}

/// The three window buttons, drawn like macOS's: coloured while the window is key, grey otherwise,
/// symbols on all three while the pointer is over any of them.
struct FullScreenControlsView: View {
    let model: FullScreenControlsModel
    weak var window: NSWindow?
    @State private var hovering = false
    @Environment(\.controlActiveState) private var active
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        // Each light at its own place (`offset`), so the rail's lights can glide between column and row.
        ZStack(alignment: .topLeading) {
            light(.close, color: Color(red: 1, green: 0.373, blue: 0.341), symbol: "xmark", label: "Close") { window?.performClose(nil) }
                .offset(at(0))
            light(.minimize, color: Color(red: 0.996, green: 0.737, blue: 0.180), symbol: "minus", label: "Minimize") { window?.miniaturize(nil) }
                .offset(at(1))
            light(.zoom, color: Color(red: 0.157, green: 0.784, blue: 0.251), symbol: (window as? BrowserWindow)?.isIkagoFullScreen == true ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                  label: "Full Screen") { window?.toggleFullScreen(nil) }
                .offset(at(2))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func at(_ index: Int) -> CGSize {
        let point = model.offset(index, progress: model.progress)
        return CGSize(width: point.x, height: point.y)
    }

    private enum Kind { case close, minimize, zoom }

    private func light(_ kind: Kind, color: Color?, symbol: String?, label: String, action: (() -> Void)?) -> some View {
        let lit = (active == .key || active == .active || hovering) && color != nil
        return Button { action?() } label: {
            ZStack {
                // Inactive lights are solid, like macOS's: see-through, they showed whatever was behind them.
                Circle().fill(lit ? color! : Color(white: scheme == .dark ? 0.33 : 0.8))
                Circle().strokeBorder(.black.opacity(0.12), lineWidth: 0.5)
                if hovering, let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: model.size * 0.5, weight: .bold))
                        .foregroundStyle(.black.opacity(0.55))
                }
            }
            .frame(width: model.size, height: model.size)
            .contentShape(Circle())
        }
        // Symbols on all three while the pointer is over any of them (the host is larger than the lights in the rail).
        .onHover { hovering = $0 }
        .buttonStyle(.plain)
        .disabled(action == nil)
        .accessibilityLabel(label)
    }
}
