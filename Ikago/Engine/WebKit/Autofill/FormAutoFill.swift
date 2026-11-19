import AppKit
import WebKit

/// Address and card filling on WebKit: the form script (`FormFillScript`) reports a focused address or card field and a
/// submitted form; Ikago lists the saved ones under the field and hands the chosen one back to the script's `fill` as call
/// arguments, never script text. Only the main frame and same-site frames (`PasswordAutoFill.mayFill`) on secure pages.
@MainActor
final class FormAutoFill: NSObject, WKScriptMessageHandler {
    static let shared = FormAutoFill()
    nonisolated static let handlerName = "ikagoFormFill"

    func install(in controller: WKUserContentController) {
        controller.addUserScript(WKUserScript(source: FormFillScript.source, injectionTime: .atDocumentEnd,
                                              forMainFrameOnly: false, in: .defaultClient))
        controller.add(self, contentWorld: .defaultClient, name: Self.handlerName)
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let webView = message.webView, let url = webView.url, AutofillFlow.isSecure(url),
              PasswordAutoFill.mayFill(message.frameInfo, in: webView),
              let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        let isPrivate = (webView.window?.windowController as? BrowserWindowController)?.state.isPrivate ?? true
        switch type {
        case "focus":
            let field = PasswordAutoFill.fieldRect(body, frame: message.frameInfo, in: webView)
            // Without the field's place (a subframe), list only after a click, which leaves the pointer on it.
            guard field != nil || body["click"] as? Bool == true else { return }
            fill(webView, frame: message.frameInfo, report: body, field: field)
        case "submitted":
            AutofillFlow.submitted(address: body["address"] as? [String: String], card: body["card"] as? [String: String],
                                   pageURL: url, isPrivate: isPrivate, in: webView)
        default: break
        }
    }

    private func fill(_ webView: WKWebView, frame: WKFrameInfo, report: [String: Any], field: NSRect?) {
        guard let url = webView.url, let responder = webView.window?.firstResponder as? NSView,
              responder === webView || responder.isDescendant(of: webView) else { return }
        Task { @MainActor in
            guard let chosen = await AutofillFlow.choose(report: report, url: url, in: webView, field: field),
                  webView.url == url, PasswordAutoFill.mayFill(frame, in: webView) else { return }
            let filled = try? await webView.callAsyncJavaScript("return window.__ikagoFormFill.fill(values, card, origin)",
                arguments: ["values": chosen.values, "card": chosen.card, "origin": PasswordAutoFill.origin(of: frame, page: url)],
                in: frame, contentWorld: .defaultClient)
            #if DEBUG
            if WebProfiles.isTestMode { print("IKTEST autofill filled \(filled as? Int ?? 0)") }
            #endif
            _ = filled
        }
    }
}
