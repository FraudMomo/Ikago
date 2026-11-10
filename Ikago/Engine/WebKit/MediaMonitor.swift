import WebKit

/// Tracks which pages are audible and applies tab muting, through a small script in the
/// isolated `.defaultClient` world of every frame (pages can't see or spoof it).
@MainActor
final class MediaMonitor: NSObject, WKScriptMessageHandler {
    static let shared = MediaMonitor()
    static let handlerName = "ikagoMedia"
    private let pages = NSMapTable<WKWebView, WebKitTab>.weakToWeakObjects()

    /// Reports "audible?" on every media event; `__ikagoSetMuted` mutes this frame's media.
    private static let source = """
        \(MediaPlaybackScript.install)
        (() => {
          let last = '';
          const report = () => {
            const state = window.__ikagoMedia.state(), json = JSON.stringify(state);
            if (last === json) return;
            last = json;
            window.webkit.messageHandlers.\(handlerName).postMessage(state);
          };
          window.__ikagoMediaChanged = report;
          window.__ikagoSetMuted = value => { window.__ikagoMedia.mute(value); report(); };
          addEventListener('pagehide', () => {
            window.webkit.messageHandlers.\(handlerName).postMessage({});
          });
          report();
        })()
        """

    /// Adds the script and handler to a new tab configuration (popups inherit them).
    func install(in controller: WKUserContentController) {
        let script = WKUserScript(source: Self.source, injectionTime: .atDocumentStart,
                                  forMainFrameOnly: false, in: .defaultClient)
        controller.addUserScript(script)
        controller.add(self, contentWorld: .defaultClient, name: Self.handlerName)
    }

    func register(_ page: WebKitTab) { pages.setObject(page, forKey: page.webView) }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let webView = message.webView, let page = pages.object(forKey: webView),
              let report = message.body as? [String: Any] else { return }
        page.frameReportedAudio(report["audible"] as? Bool ?? false,
                                playback: MediaPlaybackState(report), frame: message.frameInfo)
    }
}
