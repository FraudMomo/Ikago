import AppKit
import AVFoundation
import AVKit

/// One native video over a Chromium page: macOS's player with its standard controls, clipped to the
/// part of the page's video that is visible, and following it as the page scrolls.
@MainActor
final class NativeVideoPlayer {
    private let player: AVPlayer
    private let clip = NativeVideoClip()
    private let view = NativeVideoView()
    private weak var owner: NativeVideoOverlay?
    private weak var page: NSView?
    private let isGIF: Bool
    private var observations: [NSKeyValueObservation] = []
    private var endObserver: NSObjectProtocol?
    /// Ikago started playback and hasn't paused it: a stop it didn't ask for is the person pausing.
    private var expectingPlay = false
    private var changingMute = false
    private var personPaused = false
    private var heardAudio = false
    private var muteBeforeTab: Bool?
    var isAudible: Bool { isShown && player.rate > 0 && !player.isMuted && player.volume > 0 }
    var playback: MediaPlaybackState {
        if isAudible { heardAudio = true }
        var state = MediaPlaybackState()
        state.available = heardAudio && isShown
        state.playing = state.available && player.timeControlStatus != .paused
        return state
    }
    private(set) var moved = false
    var isShown: Bool { clip.superview != nil && !clip.isHidden }

    init(stream: NativeVideoSource.Stream, owner: NativeVideoOverlay, page: NSView) {
        player = AVPlayer(url: stream.url)
        isGIF = stream.isGIF
        self.owner = owner
        self.page = page
        player.preventsDisplaySleepDuringVideoPlayback = !stream.isGIF
        view.player = player
        view.controlsStyle = stream.isGIF ? .none : .floating
        view.showsFullScreenToggleButton = true
        view.allowsPictureInPicturePlayback = !stream.isGIF
        view.videoGravity = .resizeAspect
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        clip.wantsLayer = true
        clip.layer?.masksToBounds = true
        clip.addSubview(view)
        clip.isHidden = true
        setMuted(stream.isGIF || !owner.prefersSound)
        observations.append(player.observe(\.timeControlStatus) { [weak self] player, _ in
            MainActor.assumeIsolated {
                guard let self, player.timeControlStatus == .paused, self.expectingPlay, !self.atEnd else { return }
                self.expectingPlay = false
                self.personPaused = true
            }
        })
        observations.append(player.observe(\.isMuted) { [weak self] player, _ in
            MainActor.assumeIsolated {
                guard let self, !self.changingMute, !self.isGIF else { return }
                if self.owner?.tabMuted == true, !player.isMuted { self.setMuted(true); return }
                self.owner?.prefersSound = !player.isMuted
            }
        })
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification,
                                                             object: player.currentItem, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isGIF else { return }
                self.player.seek(to: .zero)
                self.player.play()
            }
        }
    }

    private var atEnd: Bool {
        guard let item = player.currentItem, item.duration.isNumeric else { return false }
        return player.currentTime().seconds >= item.duration.seconds - 0.25
    }

    private func setMuted(_ muted: Bool) {
        changingMute = true
        player.isMuted = muted
        changingMute = false
    }

    /// Places the player over the page's video (CSS pixels × zoom, viewport at the page's bottom) and
    /// plays or pauses it the way X does.
    func place(_ report: NativeVideoReport, zoom: CGFloat, viewport: NSRect, in page: NSView) {
        let frame = NSRect(x: report.frame.minX * zoom, y: viewport.maxY - report.frame.maxY * zoom,
                           width: report.frame.width * zoom, height: report.frame.height * zoom)
        var visible = frame.intersection(viewport)
        let topEdge = viewport.maxY - (report.frame.minY + report.hiddenTop) * zoom
        if visible.maxY > topEdge { visible.size.height = max(0, topEdge - visible.minY) }
        guard !report.covered, report.shown > 0.02, visible.width >= 8, visible.height >= 8 else { return hide() }
        if clip.superview !== page { page.addSubview(clip, positioned: .above, relativeTo: nil) }
        let clipFrame = visible.integral
        moved = clip.frame != clipFrame
        if moved { clip.frame = clipFrame }
        let inner = frame.offsetBy(dx: -clipFrame.minX, dy: -clipFrame.minY)
        if view.frame != inner { view.frame = inner }
        clip.isHidden = false
        if report.shown >= 0.5, !personPaused, player.timeControlStatus != .playing { play() }
        if report.shown < 0.25 { pause(); personPaused = false }
    }

    private func play() {
        if !isGIF { setMuted(owner?.tabMuted == true || !(owner?.prefersSound ?? false)) }
        expectingPlay = true
        player.play()
    }

    private func pause() {
        expectingPlay = false
        if player.timeControlStatus != .paused { player.pause() }
    }

    func setTabMuted(_ muted: Bool) {
        if muted {
            if muteBeforeTab == nil { muteBeforeTab = player.isMuted }
            setMuted(true)
        } else if let previous = muteBeforeTab {
            setMuted(previous); muteBeforeTab = nil
        }
    }

    func control(_ action: MediaPlaybackAction) {
        guard playback.available else { return }
        switch action {
        case .pause: personPaused = true; pause()
        case .play: personPaused = false; play()
        case .next: break
        }
    }

    /// Out of sight: paused and hidden; it keeps its place and buffer for when it comes back.
    func hide() {
        pause()
        personPaused = false
        clip.isHidden = true
        moved = false
    }

    func remove() {
        pause()
        observations.removeAll()
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        view.player = nil
        clip.removeFromSuperview()
    }
}

/// Scrolling over a native video scrolls the page, as it would over the page's own video.
@MainActor private func passScroll(_ event: NSEvent, from view: NSView) {
    var container: NSView? = view
    while let current = container, !(current is NativeVideoClip) { container = current.superview }
    guard let page = container?.superview else { return }
    let point = page.convert(event.locationInWindow, from: nil)
    for sibling in page.subviews.reversed() where !(sibling is NativeVideoClip) && !sibling.isHidden {
        if let target = sibling.hitTest(point) { target.scrollWheel(with: event); return }
    }
}

final class NativeVideoClip: NSView {
    override func scrollWheel(with event: NSEvent) { passScroll(event, from: self) }
}

private final class NativeVideoView: AVPlayerView {
    override func scrollWheel(with event: NSEvent) { passScroll(event, from: self) }
}
