import WebKit

/// WebKit's own "this page is making sound" flag, which covers what the media script can't see from its isolated
/// world: Web Audio (games, many music players), `new Audio()` elements never put in the document, and players
/// inside closed shadow roots.
// SPI: `WKWebView._isPlayingAudio` (KVO-compliant, what Safari's tab speaker uses). Guarded by `responds(to:)`;
// without it the script's reports are all there is.
@MainActor
final class PlayingAudioObserver: NSObject {
    private static let key = "_isPlayingAudio"
    private weak var webView: WKWebView?
    private let changed: @MainActor (Bool) -> Void

    init?(_ webView: WKWebView, changed: @escaping @MainActor (Bool) -> Void) {
        guard webView.responds(to: NSSelectorFromString(Self.key)) else { return nil }
        self.webView = webView
        self.changed = changed
        super.init()
        webView.addObserver(self, forKeyPath: Self.key, options: [.new], context: nil)
    }

    func stop() {
        webView?.removeObserver(self, forKeyPath: Self.key)
        webView = nil
    }

    nonisolated override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                                           change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        let playing = change?[.newKey] as? Bool ?? false
        // WebKit sends KVO on the main thread (§3.3).
        MainActor.assumeIsolated { changed(playing) }
    }
}
