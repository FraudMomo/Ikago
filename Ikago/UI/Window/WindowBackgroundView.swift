import AppKit

/// The window's backdrop: macOS's behind-window blur tinted with the Space color, so the
/// sidebar and margins are translucent without being grey.
final class WindowBackgroundView: NSVisualEffectView {
    private let tint = CALayer()
    weak var shell: NSView?
    var shellTopInset: CGFloat = 0 {
        didSet { needsLayout = true }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        material = .underWindowBackground
        blendingMode = .behindWindow
        state = .followsWindowActiveState
        wantsLayer = true
        layer?.addSublayer(tint)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func apply(_ palette: Palette, translucentSidebar: Bool = false) {
        appearance = NSAppearance(named: palette.isDark ? .darkAqua : .aqua)
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.35)
        let translucent = translucentSidebar && !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        // Only the translucent sidebar shows the desktop through the window. Otherwise the tint is solid and the
        // view stops blurring what is behind the window: WindowServer would redo that blur for the whole window
        // whenever anything behind or inside it changes, for a backdrop no one sees.
        blendingMode = translucent ? .behindWindow : .withinWindow
        state = translucent ? .followsWindowActiveState : .inactive
        tint.backgroundColor = palette.nsTint.withAlphaComponent(translucent ? 0.22 : 1).cgColor
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        // Always derive the shell from the current content bounds. Autoresizing a shell
        // shortened for fullscreen carries its old margins through titlebar/video restores.
        shell?.frame = NSRect(x: bounds.minX, y: bounds.minY, width: bounds.width,
                              height: max(0, bounds.height - shellTopInset))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        tint.frame = bounds
        CATransaction.commit()
    }
}
