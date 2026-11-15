import AppKit
import IKCEFBridge

/// Picture in Picture on Chromium, without a Chromium window: Chromium's own PiP opens a window of its own, which Ikago
/// never shows, and its pages are embedded browsers that can't hand a stream to AVKit (YouTube plays from `blob:`).
/// Instead the video goes element-fullscreen inside its page (`prepare`, with a user gesture), and the page's view moves
/// into Ikago's floating panel, where the video fills it; the tab shows a note with Back to Tab. Closing the panel, Back to
/// Tab, the page leaving fullscreen (Esc, a navigation) or the tab closing puts the view back where it was.
@MainActor
final class ChromiumPictureInPicture: NSObject, NSWindowDelegate {
    private weak var page: IKCEFPage?
    private var panel: NSPanel?
    private var saved: (superview: NSView, mask: NSView.AutoresizingMask, inset: CGFloat)?
    private var placeholder: NSView?
    private var aspect = NSSize(width: 16, height: 9)
    /// Fullscreen was requested for Picture in Picture: the page's fullscreen comes here, not to the window.
    private var pending = false
    private(set) var isActive = false
    /// Play/Pause in the panel's controls.
    var togglePlayback: (() -> Void)?

    /// In each frame's isolated world, with a user gesture: the video the page put in Chromium's own Picture in Picture
    /// (taken back out of it), else the playing (or first) ready video, goes fullscreen.
    static let prepare = """
    const own = document.pictureInPictureElement;
    if (own) await document.exitPictureInPicture().catch(() => {});
    const videos = [...document.querySelectorAll('video')].filter(v => v.readyState > 1 && v.videoWidth > 0);
    const video = (own && videos.includes(own) ? own : null) || videos.find(v => !v.paused && !v.ended) || videos[0];
    if (!video) return {video:false};
    try { await video.requestFullscreen({navigationUI: 'hide'}); }
    catch (error) { return {video:true, failed:String(error && error.message || error)}; }
    return {video:true, width:video.videoWidth, height:video.videoHeight};
    """

    init(page: IKCEFPage) { self.page = page }

    func expectFullscreen() { pending = true }
    func cancelExpectation() { pending = false }

    func setAspect(width: Double, height: Double) {
        guard width > 0, height > 0 else { return }
        aspect = NSSize(width: width, height: height)
        guard let panel else { return }
        panel.contentAspectRatio = aspect
        var frame = panel.frame
        let height = (frame.width * aspect.height / aspect.width).rounded()
        frame.origin.y += frame.height - height
        frame.size.height = height
        panel.setFrame(frame, display: true)
    }

    /// The page reported fullscreen starting or ending. True when it was Picture in Picture's.
    func pageChanged(fullscreen: Bool) -> Bool {
        if fullscreen, pending { pending = false; enter(); return true }
        if !fullscreen, isActive { leave(); return true }
        return false
    }

    private func enter() {
        guard !isActive, let page, let superview = page.superview else { return }
        isActive = true
        saved = (superview, page.autoresizingMask, page.topInset)
        let screen = page.window?.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width: CGFloat = 480, height = (width * aspect.height / aspect.width).rounded()
        let frame = NSRect(x: visible.maxX - width - 24, y: visible.minY + 24, width: width, height: height)
        let panel = NSPanel(contentRect: frame, styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.title = "Picture in Picture"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentAspectRatio = aspect
        panel.minSize = NSSize(width: 200, height: 112)
        panel.backgroundColor = .black
        panel.delegate = self
        let container = PictureInPictureContainer(frame: NSRect(origin: .zero, size: frame.size))
        container.onBack = { [weak self] in self?.end() }
        container.onPlayPause = { [weak self] in self?.togglePlayback?() }
        panel.contentView = container
        page.removeFromSuperview()
        page.topInset = 0
        page.frame = container.bounds
        page.autoresizingMask = [.width, .height]
        container.addSubview(page, positioned: .below, relativeTo: nil)
        let note = PictureInPictureNote(frame: superview.bounds)
        note.onBack = { [weak self] in self?.end() }
        note.autoresizingMask = [.width, .height]
        superview.addSubview(note)
        placeholder = note
        self.panel = panel
        panel.orderFrontRegardless()
        page.refit()
    }

    /// Back to the tab, from the panel, the note or the media island's button.
    func end() {
        guard isActive else { return }
        leave()
        page?.exitFullscreen()
    }

    private func leave() {
        guard isActive else { return }
        isActive = false
        pending = false
        placeholder?.removeFromSuperview()
        placeholder = nil
        if let page, let saved, page.superview === panel?.contentView {
            page.removeFromSuperview()
            saved.superview.addSubview(page, positioned: .below, relativeTo: nil)
            page.autoresizingMask = saved.mask.isEmpty ? [.width, .height] : saved.mask
            page.frame = saved.superview.bounds
            page.topInset = saved.inset
            page.refit()
        }
        saved = nil
        panel?.delegate = nil
        panel?.orderOut(nil)
        panel = nil
    }

    func windowWillClose(_ notification: Notification) { end() }

    /// The tab is closing or moving to another window.
    func tearDown() { end() }
}

/// The panel's content: the page under a Back to Tab and a Play/Pause button that show while the pointer is over it.
private final class PictureInPictureContainer: NSView {
    var onBack: (() -> Void)?
    var onPlayPause: (() -> Void)?
    private let controls = NSStackView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        autoresizingMask = [.width, .height]
        let back = Self.button("pip.exit", "Back to Tab") { [weak self] in self?.onBack?() }
        let play = Self.button("playpause.fill", "Play or Pause") { [weak self] in self?.onPlayPause?() }
        controls.orientation = .horizontal
        controls.spacing = 10
        controls.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        controls.addArrangedSubview(back)
        controls.addArrangedSubview(play)
        controls.wantsLayer = true
        controls.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        controls.layer?.cornerRadius = Radius.control
        controls.alphaValue = 0
        controls.translatesAutoresizingMaskIntoConstraints = false
        addSubview(controls)
        NSLayoutConstraint.activate([
            controls.centerXAnchor.constraint(equalTo: centerXAnchor),
            controls.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
        ])
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        if subview !== controls { addSubview(controls, positioned: .above, relativeTo: nil) }  // controls stay on top
    }
    override func mouseEntered(with event: NSEvent) { fade(1) }
    override func mouseExited(with event: NSEvent) { fade(0) }
    private func fade(_ alpha: CGFloat) {
        NSAnimationContext.runAnimationGroup { $0.duration = 0.15; controls.animator().alphaValue = alpha }
    }

    private static func button(_ symbol: String, _ label: String, action: @escaping () -> Void) -> NSButton {
        let button = ClosureButton(action: action)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .medium))
        button.contentTintColor = .white
        button.isBordered = false
        button.toolTip = label
        return button
    }
}

/// What the tab shows while its video plays in the panel.
private final class PictureInPictureNote: NSView {
    var onBack: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        let label = NSTextField(labelWithString: "Playing in Picture in Picture")
        label.textColor = NSColor.white.withAlphaComponent(0.75)
        label.font = .systemFont(ofSize: 14, weight: .medium)
        let back = ClosureButton { [weak self] in self?.onBack?() }
        back.title = "Back to Tab"
        back.bezelStyle = .rounded
        let stack = NSStackView(views: [label, back])
        stack.orientation = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo: centerXAnchor),
                                     stack.centerYAnchor.constraint(equalTo: centerYAnchor)])
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
}

private final class ClosureButton: NSButton {
    private let run: () -> Void
    init(action: @escaping () -> Void) {
        run = action
        super.init(frame: .zero)
        target = self
        self.action = #selector(fire)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    @objc private func fire() { run() }
}
