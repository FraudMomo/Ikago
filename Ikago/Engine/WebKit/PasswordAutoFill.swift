import AppKit
import WebKit

/// Fills sign-in fields on WebKit, from one of two sources (`PasswordSource`). Apple Passwords: the
/// system's own AutoFill panel types the chosen login into the focused field, so Ikago never sees it.
/// Ikago's vault: a login picked natively and unlocked with Touch ID (`PasswordChooser`), handed to
/// the key script's `fill` in the isolated world. Saving isn't possible yet: macOS has no public
/// save API for browsers, and the vault only imports for now.
@MainActor
final class PasswordAutoFill: NSObject, WKScriptMessageHandlerWithReply {
    static let shared = PasswordAutoFill()
    nonisolated static let handlerName = "ikagoPasswords"
    private var lastOpen = Date.distantPast
    #if DEBUG
    private(set) var testRequests = 0
    #endif

    /// Adds the key script and its handler to a new tab configuration (popups inherit them).
    func install(in controller: WKUserContentController) {
        let script = WKUserScript(source: PasswordKeyScript.source, injectionTime: .atDocumentEnd,
                                  forMainFrameOnly: false, in: .defaultClient)
        controller.addUserScript(script)
        controller.addScriptMessageHandler(self, contentWorld: .defaultClient, name: Self.handlerName)
    }

    var isEnabled: Bool {
        guard BrowserSecurity.shared.preferences.passwordAutoFill ?? true else { return false }
        return PasswordSource.current == .ikago || SystemPasswordPanel.isAvailable
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void) {
        guard let webView = message.webView, isEnabled, Self.mayFill(message.frameInfo, in: webView),
              let kind = (message.body as? [String: Any])?["type"] as? String else { return replyHandler(false, nil) }
        let vault = PasswordSource.current == .ikago
        switch kind {
        case "query": replyHandler(vault ? PasswordChooser.offers(for: webView.url) : true, nil)
        case "fill" where vault:
            replyHandler(true, nil)
            fillFromVault(webView, frame: message.frameInfo)
        case "fill": replyHandler(open(for: webView), nil)
        default: replyHandler(false, nil)
        }
    }

    /// The key's frame gets the login, if it is still showing the page the key was clicked on.
    private func fillFromVault(_ webView: WKWebView, frame: WKFrameInfo) {
        guard let url = webView.url, isFocused(webView) else { return }
        Task { @MainActor in
            guard let login = await PasswordChooser.choose(for: url, in: webView), webView.url == url,
                  Self.mayFill(frame, in: webView) else { return }
            _ = try? await webView.callAsyncJavaScript("return window.__ikagoPasswordKey.fill(username, password, origin)",
                arguments: ["username": login.username, "password": login.password, "origin": PasswordChooser.origin(of: url)],
                in: frame, contentWorld: .defaultClient)
            #if DEBUG
            if WebProfiles.isTestMode { print("IKTEST passwords vault filled") }
            #endif
        }
    }

    private func isFocused(_ webView: WKWebView) -> Bool {
        guard let responder = webView.window?.firstResponder as? NSView else { return false }
        return responder === webView || responder.isDescendant(of: webView)
    }

    /// The main frame of a web page, or a frame with the same origin. Cross-origin frames
    /// (ads, embeds) never get the key.
    static func mayFill(_ frame: WKFrameInfo, in webView: WKWebView) -> Bool {
        guard let url = webView.url, let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return false }
        if frame.isMainFrame { return true }
        let origin = frame.securityOrigin
        let defaultPort = scheme == "https" ? 443 : 80
        return origin.protocol.lowercased() == scheme && origin.host.lowercased() == url.host?.lowercased()
            && (origin.port == 0 ? defaultPort : origin.port) == (url.port ?? defaultPort)
    }

    /// Opens Apple's panel at the page's focused field, only while this page has the keyboard.
    private func open(for webView: WKWebView) -> Bool {
        guard let window = webView.window, let responder = window.firstResponder as? NSView,
              responder === webView || responder.isDescendant(of: webView),
              Date().timeIntervalSince(lastOpen) > 0.75 else { return false }
        #if DEBUG
        if WebProfiles.isTestMode {  // the panel would take focus from unattended checks
            lastOpen = Date()
            testRequests += 1
            print("IKTEST passwords panel requested (not shown)")
            return true
        }
        #endif
        guard NSApp.isActive, window.isKeyWindow else { return false }
        lastOpen = Date()
        return SystemPasswordPanel.open()
    }
}

/// Apple's Passwords panel (Touch ID, search, pick), opened through the Edit ▸ AutoFill ▸
/// Passwords… item AppKit adds to every app's Edit menu.
// SPI: AppKit names that item "_handleInsertFromPasswordsCommand:" (identifier and action); there is
// no public way to open the panel. If AppKit renames it, the item isn't found and the key stays hidden.
// Verified on macOS 27.2 for password and username fields in WKWebView.
@MainActor
enum SystemPasswordPanel {
    static let command = "_handleInsertFromPasswordsCommand:"

    static var isAvailable: Bool { item(in: NSApp.mainMenu) != nil }

    static func open() -> Bool {
        guard let (menu, index) = item(in: NSApp.mainMenu) else { return false }
        // AppKit refreshes the AutoFill items for the focused field only when the Edit menu
        // opens, so announce the open and close a real menu click would.
        let edit = menu.supermenu ?? menu
        edit.update()
        NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: edit)
        defer { DispatchQueue.main.async { NotificationCenter.default.post(name: NSMenu.didEndTrackingNotification, object: edit) } }
        menu.update()
        guard menu.items[index].isEnabled else { return false }
        menu.performActionForItem(at: index)
        return true
    }

    private static func item(in menu: NSMenu?) -> (NSMenu, Int)? {
        guard let menu else { return nil }
        for (index, entry) in menu.items.enumerated() {
            if entry.identifier?.rawValue == command || entry.action.map(NSStringFromSelector) == command { return (menu, index) }
            if let found = item(in: entry.submenu) { return found }
        }
        return nil
    }
}
