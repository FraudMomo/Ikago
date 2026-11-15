import SwiftUI

/// The Shift-click preview (Peek): the linked page in a large floating card over the dimmed window, with a small glass
/// column beside it to close it or keep it as a tab. Nothing is added to the tab list unless the person keeps it.
struct LivePeekPanel: View {
    let page: NSView
    let tab: TabItem?
    weak var commands: BrowserCommands?
    let colors: Palette
    /// Growing into its tab: the address and buttons fade, and the card takes the page's corners.
    var expanding = false
    /// While growing, the page's final size (the tab's page area): the page takes it once as the card starts to grow
    /// and keeps it, pinned to the card's top-left corner, while the card's clip grows around it.
    var finalPageSize: CGSize?

    /// Room the address above the card and the buttons beside it take.
    static let addressHeight: CGFloat = 34
    static let controlsWidth: CGFloat = 46

    /// Where the panel sits over a window of `size`: inset from the edges, at most 1180 pt wide, centred.
    static func frame(in size: CGSize) -> CGRect {
        let outer = min(1180, size.width)
        let x = (size.width - outer) / 2 + 64
        return CGRect(x: x, y: 14, width: max(0, outer - 82), height: max(0, size.height - 54))
    }

    /// The panel placed so its page card covers `page` exactly.
    static func frame(around page: CGRect) -> CGRect {
        CGRect(x: page.minX, y: page.minY - addressHeight, width: page.width + controlsWidth, height: page.height + addressHeight)
    }

    var body: some View {
        let card = RoundedRectangle(cornerRadius: expanding ? Radius.card : Radius.sheet, style: .continuous)
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 8) {
                address
                PeekContent(view: page, radius: expanding ? Radius.card : Radius.sheet, fixedSize: expanding ? finalPageSize : nil)
                    .background(colors.pageBackground)
                    .clipShape(card)
                    .overlay(card.strokeBorder(colors.separator, lineWidth: 0.5).opacity(expanding ? 0 : 1).allowsHitTesting(false))
                    .background(CardShadow(shape: card, color: .black.opacity(expanding ? 0 : 0.3), radius: 28, y: 10))
            }
            controls.opacity(expanding ? 0 : 1)
        }
        .allowsHitTesting(!expanding)
        .environment(\.colorScheme, colors.isDark ? .dark : .light)
        .task { await Task.yield(); commands?.focusPeek() }
        .onExitCommand { commands?.closePeek() }
    }

    /// The site, so it's clear what is being previewed; a fine progress line while it loads.
    private var address: some View {
        addressPill.opacity(expanding ? 0 : 1)
    }

    private var addressPill: some View {
        HStack(spacing: 6) {
            if let tab {
                FaviconView(tab: tab, size: 12)
                Text(tab.addressLabel).lineLimit(1).truncationMode(.middle)
            }
        }
        .font(.system(size: 11.5, weight: .medium))
        .foregroundStyle(colors.text.opacity(0.85))
        .padding(.horizontal, 12).frame(height: 26)
        .background { if !colors.glass { Capsule().fill(colors.panel) } }
        .glassControl(Capsule(), colors, reacts: false)
        .overlay(alignment: .bottom) { PageLoadProgress(tab: tab, colors: colors).padding(.horizontal, 12) }
        .frame(maxWidth: .infinity)
    }

    private var controls: some View {
        VStack(spacing: 2) {
            button("xmark", label: "Close Preview (Esc)") { commands?.closePeek() }
            button("arrow.up.forward.app", label: "Open as Tab") { commands?.openPeek() }
        }
        .padding(.vertical, 4)
        .frame(width: 36)
        .background { if !colors.glass { Capsule().fill(colors.panel) } }
        .environment(\.inGlassGroup, true)
        .glassEffect(colors.glass ? .regular.interactive() : .identity, in: Capsule())
        .padding(.top, 34)
    }

    private func button(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(colors.text.opacity(0.85))
                .frame(width: 30, height: 30).contentShape(Circle())
        }
        .buttonStyle(CircleHoverButtonStyle(colors: colors))
        .help(label).accessibilityLabel(label)
    }
}

/// The card's page area. The live page never goes inside SwiftUI's host: a Chromium page moved out of one into its tab
/// kept drawing for its old place (shifted up, a band at the bottom). This placeholder only reports where the card is;
/// the page sits in a plain AppKit view over the window (`PeekPageLayer`) that follows it, also during the zoom.
private struct PeekContent: FillingViewRepresentable {
    let view: NSView
    var radius: CGFloat = Radius.sheet
    var fixedSize: CGSize?
    func makeNSView(context: Context) -> PeekAnchorView { PeekAnchorView() }
    func updateNSView(_ anchor: PeekAnchorView, context: Context) {
        anchor.page = view
        anchor.radius = radius
        anchor.fixedSize = fixedSize
        anchor.place()
    }
    static func dismantleNSView(_ anchor: PeekAnchorView, coordinator: ()) { anchor.detach() }
}

final class PeekAnchorView: NSView {
    weak var page: NSView?
    var radius: CGFloat = Radius.sheet
    /// The page's size while the card grows into the tab (`LivePeekPanel.finalPageSize`).
    var fixedSize: CGSize?
    private let layerView = PeekPageLayer()

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func setFrameOrigin(_ origin: NSPoint) { super.setFrameOrigin(origin); place() }
    override func setFrameSize(_ size: NSSize) { super.setFrameSize(size); place() }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); if window == nil { detach() } else { place() } }

    /// Puts the page over this placeholder, in the window's content view (above the shell, as a plain AppKit view).
    func place() {
        guard let page, let window, let content = window.contentView, !isHiddenOrHasHiddenAncestor else { return }
        if layerView.superview !== content { content.addSubview(layerView, positioned: .above, relativeTo: nil) }
        layerView.frame = content.convert(bounds, from: self)
        layerView.layer?.cornerRadius = radius
        if page.superview !== layerView {
            page.removeFromSuperview()  // from a previous card only; never from the window while it's in one
            layerView.addSubview(page)
        }
        page.isHidden = false
        // Never resized frame by frame: Chromium's own layers drift from its view under a stream of animated resizes
        // (measured: 36 pt taller after the grow, so the kept page drew shifted up, and no later resize undoes it).
        // Growing, the page takes its final size once and only its origin follows the card's top-left corner.
        let frame: CGRect
        if let fixedSize {
            page.autoresizingMask = []
            frame = CGRect(x: 0, y: layerView.isFlipped ? 0 : layerView.bounds.height - fixedSize.height, width: fixedSize.width, height: fixedSize.height)
        } else {
            page.autoresizingMask = [.width, .height]
            frame = layerView.bounds
        }
        if page.frame != frame { page.frame = frame }
    }

    func detach() {
        // The page itself leaves only by its controller (closed, or kept as a tab); the clip view goes with the card.
        layerView.removeFromSuperview()
    }
}

/// The rounded clip the Peek page sits in, over the window.
final class PeekPageLayer: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerCurve = .continuous
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
}
