import AppKit

/// The address of the link under the pointer, in a small pill at the page's bottom-left corner.
/// Plain AppKit on the page's own host: hovering links never touches the SwiftUI shell.
final class LinkStatusView: NSVisualEffectView {
    private let label = NSTextField(labelWithString: "")
    private var hide: DispatchWorkItem?
    private static let margin: CGFloat = 8
    private static let padding: CGFloat = 8
    private static let height: CGFloat = 22

    init() {
        super.init(frame: .zero)
        material = .menu
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = 0.5
        alphaValue = 0
        isHidden = true
        label.font = .systemFont(ofSize: 11)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingMiddle
        label.maximumNumberOfLines = 1
        addSubview(label)
        setAccessibilityElement(false)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    /// The page keeps every click and move.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateLayer() {
        super.updateLayer()
        layer?.borderColor = NSColor.separatorColor.cgColor
    }

    /// Shows `text` at once; nil fades the pill out after a moment, so moving between links doesn't flicker.
    func show(_ text: String?, in host: NSView) {
        hide?.cancel()
        guard let text, !text.isEmpty else {
            let work = DispatchWorkItem { [weak self] in self?.fade(to: 0) }
            hide = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
            return
        }
        if label.stringValue != text { label.stringValue = text }
        place(in: host)
        fade(to: 1)
    }

    /// Bottom-left, as wide as the address needs, up to 60 % of the page.
    func place(in host: NSView) {
        let limit = max(120, min(host.bounds.width * 0.6, 560))
        let width = min(limit, ceil(label.intrinsicContentSize.width) + Self.padding * 2)
        frame = NSRect(x: Self.margin, y: Self.margin, width: width, height: Self.height)
        let textHeight = ceil(label.intrinsicContentSize.height)
        label.frame = NSRect(x: Self.padding, y: ((Self.height - textHeight) / 2).rounded(), width: width - Self.padding * 2, height: textHeight)
    }

    /// Fades in while rising a few points, and fades out in place.
    private func fade(to alpha: CGFloat) {
        if alpha > 0 { isHidden = false }
        guard alphaValue != alpha else { return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            alphaValue = alpha
            isHidden = alpha == 0
            return
        }
        let rest = NSPoint(x: Self.margin, y: Self.margin)
        if alpha > 0, alphaValue == 0 { setFrameOrigin(NSPoint(x: rest.x, y: rest.y - 5)) }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = alpha > 0 ? 0.2 : 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            animator().alphaValue = alpha
            if alpha > 0 { animator().setFrameOrigin(rest) }
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated { if let self, self.alphaValue == 0 { self.isHidden = true } }
        })
    }
}
