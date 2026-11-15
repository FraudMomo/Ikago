import WebKit

/// Gives each WebKit page the notification shim (`NotificationShim`) and receives what it sends.
@MainActor
final class WebNotificationBridge: NSObject, WKScriptMessageHandler {
    static let shared = WebNotificationBridge()

    func install(in controller: WKUserContentController) {
        controller.addUserScript(WKUserScript(source: NotificationShim.webKit, injectionTime: .atDocumentStart,
                                              forMainFrameOnly: true, in: .page))
        controller.add(self, contentWorld: .page, name: NotificationShim.webKitHandler)
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let text = message.body as? String,
              let view = message.webView as? FileDropWebView else { return }
        view.onNotification(text)
    }
}

extension WebKitTab {
    func sendNotificationMessage(_ message: [String: Any]) {
        guard let script = NotificationShim.replyScript(message) else { return }
        webView.evaluateJavaScript(script, in: nil, in: .page) { _ in }
    }
}
