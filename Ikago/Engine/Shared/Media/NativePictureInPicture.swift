import AppKit
import AVKit

/// A native floating video player for directly playable web media. WebKit also retains
/// its own Picture in Picture menu for streams that cannot be reopened by AVFoundation.
@MainActor
final class NativePictureInPicture: NSObject, NSWindowDelegate {
    static let shared = NativePictureInPicture()
    private var panel: NSPanel?
    private var player: AVPlayer?
    private weak var owner: WebTab?
    private var status: NSKeyValueObservation?

    func open(_ address: String, owner: WebTab, window: NSWindow?) {
        guard let url = URL(string: address), ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              url.user == nil, url.password == nil else { return }
        close()
        self.owner = owner
        let player = AVPlayer(url: url)
        self.player = player
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .floating
        view.showsFullScreenToggleButton = false
        view.allowsPictureInPicturePlayback = true
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 480, height: 270),
                            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Video"
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.contentAspectRatio = NSSize(width: 16, height: 9)
        panel.minSize = NSSize(width: 240, height: 160)
        panel.contentView = view
        panel.delegate = self
        panel.center()
        panel.orderFront(nil)
        self.panel = panel
        status = player.currentItem?.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            let ready = item.status == .readyToPlay, failed = item.status == .failed
            Task { @MainActor [weak self] in
                guard let self, self.player === player else { return }
                if ready {
                    await self.owner?.controlMedia(.pause)
                    player.play()
                } else if failed {
                    self.close()
                    let alert = NSAlert()
                    alert.messageText = "This video can’t open in the native player"
                    alert.informativeText = "This stream is managed by the page or requires the site’s sign-in. Keep playing it in the tab."
                    if let window { alert.beginSheetModal(for: window) { _ in } }
                }
            }
        }
    }

    func windowWillClose(_ notification: Notification) { close() }
    private func close() {
        status = nil
        player?.pause()
        player = nil
        owner = nil
        panel?.delegate = nil
        panel?.orderOut(nil)
        panel = nil
    }
}
