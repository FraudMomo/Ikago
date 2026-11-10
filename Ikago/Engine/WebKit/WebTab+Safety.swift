import AppKit
import WebKit

/// Guards against pages abusing the browser: opening other apps, dialog loops, crash loops.
extension WebKitTab {
    /// Direct links, sign-in redirects and scripted app handoffs share one confirmed route.
    func openExternal(_ url: URL, from frame: WKFrameInfo?) async {
        let host = frame?.securityOrigin.host ?? webView.url?.host ?? ""
        await externalLinks.open(url, sourceHost: host, in: webView.window)
    }

    /// A page may not open itself as a top-level data: document (a common phishing trick).
    /// Images are fine, except SVG, which is a scriptable document.
    static func blocksTopLevelData(_ url: URL, action: WKNavigationAction) -> Bool {
        guard action.targetFrame?.isMainFrame ?? true else { return false }
        return isBlockedDataDocument(url)
    }

    static func isBlockedDataDocument(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "data" else { return false }
        let text = url.absoluteString.lowercased()
        return !text.hasPrefix("data:image/") || text.hasPrefix("data:image/svg")
    }

    /// The web content process died. Reload once; if it dies again soon, stop and say so
    /// instead of looping.
    func recoverFromCrash() {
        if let last = lastCrash, Date().timeIntervalSince(last) < 30 {
            delegate?.webTab(self, didFailLoad: "This page stopped working again, so Ikago didn’t reload it.", url: currentURL)
            return
        }
        lastCrash = Date()
        webView.reload()
    }
}
