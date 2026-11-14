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
          // This document's own key: a frame's address changes without a new document (pushState), which left the
          // old address's report behind, stuck on "playing".
          const documentID = Math.random().toString(36).slice(2);
          const report = () => {
            const state = window.__ikagoMedia.state(), json = JSON.stringify(state);
            if (last === json) return;
            last = json;
            window.webkit.messageHandlers.\(handlerName).postMessage({...state, documentID});
          };
          // Media events come in bursts (a grid of videos starting and stopping while scrolling): report once per burst.
          let timer = 0;
          window.__ikagoMediaChanged = () => { if (!timer) timer = setTimeout(() => { timer = 0; report(); }, 120); };
          window.__ikagoSetMuted = value => { window.__ikagoMedia.mute(value); report(); };
          addEventListener('pagehide', () => {
            last = '';
            window.webkit.messageHandlers.\(handlerName).postMessage({documentID, gone: true});
          });
          report();
        })()
        """

    /// Adds the script and handler to a new tab configuration (popups inherit them).
    func install(in controller: WKUserContentController) {
        #if DEBUG
        if DebugEnvironment.value("IKAGO_NO_MEDIA_SCRIPT") != nil { return }  // performance comparisons only
        #endif
        let script = WKUserScript(source: Self.source, injectionTime: .atDocumentStart,
                                  forMainFrameOnly: false, in: .defaultClient)
        controller.addUserScript(script)
        controller.add(self, contentWorld: .defaultClient, name: Self.handlerName)
    }

    func register(_ page: WebKitTab) { pages.setObject(page, forKey: page.webView) }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let webView = message.webView, let page = pages.object(forKey: webView),
              let report = message.body as? [String: Any] else { return }
        let document = report["documentID"] as? String ?? message.frameInfo.request.url?.absoluteString ?? ""
        if report["gone"] as? Bool == true { return page.documentGone(document) }
        page.frameReportedAudio(report["audible"] as? Bool ?? false,
                                playback: MediaPlaybackState(report), frame: message.frameInfo, document: document)
    }
}
