import WebKit

/// Reports the link under the pointer for the status bar, through a small script in the isolated `.defaultClient`
/// world of every frame. Public API only: WebKit's own hover callback is private.
@MainActor
final class LinkHoverMonitor: NSObject, WKScriptMessageHandler {
    static let shared = LinkHoverMonitor()
    static let handlerName = "ikagoLinkHover"
    private let pages = NSMapTable<WKWebView, WebKitTab>.weakToWeakObjects()

    /// Posts the hovered link's address when it changes, and "" when the pointer leaves links or the frame.
    private static let source = """
        (() => {
          let last = ''
          const report = href => {
            if (href === last) return
            last = href
            window.webkit.messageHandlers.\(handlerName).postMessage(href.slice(0, 2048))
          }
          document.addEventListener('mouseover', event => {
            const link = event.target instanceof Element ? event.target.closest('a[href], area[href]') : null
            report(link && typeof link.href === 'string' ? link.href : '')
          }, { capture: true, passive: true })
          document.addEventListener('mouseout', event => { if (!event.relatedTarget) report('') },
                                    { capture: true, passive: true })
          window.addEventListener('pagehide', () => report(''))
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
              let href = message.body as? String else { return }
        page.delegate?.webTab(page, didHoverLink: href.isEmpty ? nil : href)
    }
}
