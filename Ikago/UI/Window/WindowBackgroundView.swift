import AppKit

/// The window's backdrop, under the whole shell. With the frosted sidebar it is the one frosted layer everything sits on:
/// macOS's behind-window blur (the sidebar material, vibrant, so the desktop really shows through) under a light wash of
/// the Space color. The sidebar, rail and tab row draw no material of their own on top, so nothing stacks into a flatter,
/// greyer look. Otherwise it is a solid Space color and blurs nothing.
final class WindowBackgroundView: NSView {
    private let frost = NSVisualEffectView()
    private let tint = NSView()
    weak var shell: NSView?
    var shellTopInset: CGFloat = 0 {
        didSet { needsLayout = true }
    }

    /// How much of the Space color lies over the blur. Low enough that the desktop's own colors come through.
    static let frostTint: CGFloat = 0.14

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        frost.material = .sidebar
        frost.blendingMode = .behindWindow
        frost.state = .followsWindowActiveState
        frost.isHidden = true
        tint.wantsLayer = true
        addSubview(frost)
        addSubview(tint)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func apply(_ palette: Palette, translucentSidebar: Bool = false) {
        appearance = NSAppearance(named: palette.isDark ? .darkAqua : .aqua)
        let translucent = translucentSidebar && !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        // Vibrant appearances are the see-through versions of the material; the plain ones are nearly opaque. Only the
        // blur view gets one, so the shell's own controls keep the window's appearance.
        frost.appearance = NSAppearance(named: palette.isDark ? .vibrantDark : .vibrantLight)
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.35)
        // Hidden, the blur costs nothing: WindowServer would otherwise redo it for the whole window whenever anything
        // behind or inside it changes, for a backdrop no one sees.
        frost.isHidden = !translucent
        tint.layer?.backgroundColor = palette.nsTint.withAlphaComponent(translucent ? Self.frostTint : 1).cgColor
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        // Always derive the shell from the current content bounds. Autoresizing a shell
        // shortened for fullscreen carries its old margins through titlebar/video restores.
        shell?.frame = NSRect(x: bounds.minX, y: bounds.minY, width: bounds.width,
                              height: max(0, bounds.height - shellTopInset))
        frost.frame = bounds
        tint.frame = bounds
    }
}
