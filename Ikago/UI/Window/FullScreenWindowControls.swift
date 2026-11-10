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
    private var host: NSHostingView<FullScreenControlsView>?
    /// The windowed traffic lights, measured from the content view's top-left, for layouts that leave
    /// them where AppKit puts them (Sidebar).
    private var measured: (firstX: CGFloat, centerFromTop: CGFloat, spacing: CGFloat, size: CGFloat)?

    init(window: NSWindow) { self.window = window }

    var isShown: Bool { host != nil }
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

    func show() {
        guard let window, let content = window.contentView, host == nil else { return }
        let host = NSHostingView(rootView: FullScreenControlsView(model: model, window: window))
        host.sizingOptions = []
        host.safeAreaRegions = []
        // Just above the shell (the first subview), so a page lifted for video fullscreen stays on top.
        content.addSubview(host, positioned: .above, relativeTo: content.subviews.first)
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

@MainActor
@Observable
final class FullScreenControlsModel {
    var size: CGFloat = 14
    var spacing: CGFloat = 23
    var vertical = false
}

/// The three window buttons, drawn like macOS's: coloured while the window is key, grey otherwise,
/// symbols on all three while the pointer is over any of them.
struct FullScreenControlsView: View {
    let model: FullScreenControlsModel
    weak var window: NSWindow?
    @State private var hovering = false
    @Environment(\.controlActiveState) private var active

    var body: some View {
        let stack = model.vertical ? AnyLayout(VStackLayout(spacing: model.spacing - model.size)) : AnyLayout(HStackLayout(spacing: model.spacing - model.size))
        stack {
            light(.close, color: Color(red: 1, green: 0.373, blue: 0.341), symbol: "xmark", label: "Close") { window?.performClose(nil) }
            light(.minimize, color: Color(red: 0.996, green: 0.737, blue: 0.180), symbol: "minus", label: "Minimize") { window?.miniaturize(nil) }
            light(.zoom, color: Color(red: 0.157, green: 0.784, blue: 0.251), symbol: (window as? BrowserWindow)?.isIkagoFullScreen == true ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                  label: "Full Screen") { window?.toggleFullScreen(nil) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onHover { hovering = $0 }
    }

    private enum Kind { case close, minimize, zoom }

    private func light(_ kind: Kind, color: Color?, symbol: String?, label: String, action: (() -> Void)?) -> some View {
        let lit = (active == .key || active == .active || hovering) && color != nil
        return Button { action?() } label: {
            ZStack {
                Circle().fill(lit ? color! : Color.gray.opacity(0.35))
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
        .buttonStyle(.plain)
        .disabled(action == nil)
        .accessibilityLabel(label)
    }
}
