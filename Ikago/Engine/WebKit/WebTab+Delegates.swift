import AppKit
import WebKit

// MARK: - WKNavigationDelegate

extension WebKitTab: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 preferences: WKWebpagePreferences) async -> (WKNavigationActionPolicy, WKWebpagePreferences) {
        guard let url = action.request.url else { return (.cancel, preferences) }
        preferences.preferredHTTPSNavigationPolicy = BrowserSecurity.shared.httpsPolicy(for: url)
        let scheme = url.scheme?.lowercased() ?? ""

        // WKNavigationAction uses a button mask: middle is 4 (NSEvent uses index 2).
        // Auxiliary navigation can also be .other instead of .linkActivated.
        let flags = action.modifierFlags
        let newTabGesture = action.buttonNumber == 4 || (action.navigationType == .linkActivated && flags.contains(.command))
        if newTabGesture, AddressResolver.isPageURL(url.absoluteString) || ["chrome-extension", "webkit-extension"].contains(scheme) {
            delegate?.webTab(self, openInNewTab: url.absoluteString, background: !flags.contains(.shift))
            return (.cancel, preferences)
        }
        if action.targetFrame?.isMainFrame == true, delegate?.webTab(self, blocksUnsafeNavigation: url) == true {
            return (.cancel, preferences)
        }
        if action.targetFrame?.isMainFrame == true, delegate?.webTab(self, handsOff: url, method: action.request.httpMethod ?? "GET") == true {
            return (.cancel, preferences)
        }
        if action.targetFrame?.isMainFrame == true, BrowserSecurity.shared.requiresHTTPS(url) {
            guard action.request.httpMethod == nil || action.request.httpMethod == "GET" || action.request.httpMethod == "HEAD",
                  httpsUpgradeAttempts < 3, let secure = BrowserSecurity.secureURL(url) else {
                delegate?.webTab(self, didFailLoad: "HTTPS-only mode blocked an insecure request. This site must support HTTPS to open.", url: url.absoluteString)
                return (.cancel, preferences)
            }
            httpsUpgradeAttempts += 1
            delegate?.webTab(self, willUpgradeToHTTPS: url)
            var request = action.request; request.url = secure
            webView.load(request)
            return (.cancel, preferences)
        }
        if action.shouldPerformDownload {
            return (await delegate?.webTab(self, mayDownload: url) == true ? .download : .cancel, preferences)
        }
        if scheme == "chrome-extension" {
            if action.targetFrame?.isMainFrame == true {
                delegate?.webTab(self, navigateToExtension: url.absoluteString)
            } else if action.targetFrame == nil {
                delegate?.webTab(self, openInNewTab: url.absoluteString, background: false)
            }
            return (.cancel, preferences)
        }

        if Self.blocksTopLevelData(url, action: action) { return (.cancel, preferences) }
        if ["http", "https", "about", "blob", "data", "file", "webkit-extension"].contains(scheme) {
            return (.allow, preferences)
        }
        if ExternalLinkOpener.isExternal(url), ExternalLinkOpener.permits(action) {
            // Cancel WebKit's navigation before showing a sheet or activating another app.
            // Holding the policy decision open can stall an OAuth popup's navigation lifecycle.
            Task { @MainActor in await self.openExternal(url, from: action.sourceFrame) }
        }
        return (.cancel, preferences)
    }

    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        guard response.isForMainFrame else { return .allow }
        var wantsDownload = !response.canShowMIMEType
        if let http = response.response as? HTTPURLResponse,
           let disposition = http.value(forHTTPHeaderField: "Content-Disposition"),
           disposition.lowercased().hasPrefix("attachment") {
            wantsDownload = true
        }
        guard wantsDownload else { return .allow }
        return await delegate?.webTab(self, mayDownload: response.response.url) == true ? .download : .cancel
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        DownloadCenter.shared.track(download, isPrivate: WebProfiles.isPrivateStore(webView.configuration.websiteDataStore))
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        DownloadCenter.shared.track(download, isPrivate: WebProfiles.isPrivateStore(webView.configuration.websiteDataStore))
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        httpsUpgradeAttempts = 0
        dialogsShown = 0; dialogsBlocked = false
        resetMedia()
        delegate?.webTab(self, didCommit: currentURL)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if isMuted { applyMute() }
        let script = """
            (() => { const l = document.querySelector('link[rel~="icon"], link[rel="apple-touch-icon"]');
                     return l ? l.href : null })()
            """
        let documentURL = currentURL
        webView.evaluateJavaScript(script, in: nil, in: .defaultClient) { [weak self] result in
            guard let self, self.currentURL == documentURL else { return }
            let href = (try? result.get()) as? String
            self.delegate?.webTab(self, didFindFavicon: href.flatMap(URL.init(string:)))
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        report(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        report(error)
    }

    private func report(_ error: Error) {
        let ns = error as NSError
        // Cancelled (a newer load replaced it) or turned into a download: not failures.
        if ns.domain == NSURLErrorDomain, ns.code == NSURLErrorCancelled { return }
        if ns.domain == "WebKitErrorDomain", ns.code == 102 { return }  // frame load interrupted by policy
        let failed = (ns.userInfo[NSURLErrorFailingURLErrorKey] as? URL)?.absoluteString
        delegate?.webTab(self, didFailLoad: ns.localizedDescription, url: failed)
    }

    /// The page's process crashed or was killed under memory pressure: bring it back.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        recoverFromCrash()
    }
}

// MARK: - WKUIDelegate

extension WebKitTab: WKUIDelegate {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let target = action.request.url, ExternalLinkOpener.isExternal(target) {
            if ExternalLinkOpener.permits(action) {
                Task { @MainActor in await self.openExternal(target, from: action.sourceFrame) }
            }
            return nil
        }
        let url = action.request.url?.absoluteString ?? "about:blank"
        let background = (action.modifierFlags.contains(.command) || action.buttonNumber == 4) && !action.modifierFlags.contains(.shift)
        // A clicked link to a site another engine opens: a plain new tab there. Scripted windows (sign-in) stay
        // here, because they need window.opener.
        if action.navigationType == .linkActivated, let target = action.request.url, delegate?.webTab(self, usesOtherEngine: target) == true {
            delegate?.webTab(self, openInNewTab: target.absoluteString, background: background)
            return nil
        }
        return delegate?.webTab(self, popupWith: configuration, url: url, background: background)
    }

    // SPI: WKUIDelegatePrivate. WebKit's PDF viewer download button calls this instead of starting a WKDownload.
    @objc(_webView:saveDataToFile:suggestedFilename:mimeType:originatingURL:)
    func webView(_ webView: WKWebView, saveDataToFile data: Data, suggestedFilename: String, mimeType: String?, originatingURL: URL?) {
        DownloadCenter.shared.save(data, suggestedFilename: suggestedFilename, sourceURL: originatingURL ?? webView.url,
                                   isPrivate: WebProfiles.isPrivateStore(webView.configuration.websiteDataStore))
    }

    func webViewDidClose(_ webView: WKWebView) {
        delegate?.webTabDidClose(self)
    }

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void) {
        let origin = "\(origin.protocol)://\(origin.host)\(origin.port > 0 ? ":\(origin.port)" : "")"
        let request = PermissionRequest(origin: origin, kinds: PermissionRequest.kinds(for: type),
                                        handler: decisionHandler)
        if let delegate { delegate.webTab(self, requestsPermission: request) } else { request.resolve(.deny) }
    }

    // JavaScript dialogs: native sheets on the tab's window.

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async {
        _ = await presentDialog(message, frame: frame, buttons: ["OK"])
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async -> Bool {
        await presentDialog(message, frame: frame, buttons: ["OK", "Cancel"]) == .alertFirstButtonReturn
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo) async -> String? {
        let field = NSTextField(string: defaultText ?? "")
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        let result = await presentDialog(prompt, frame: frame, buttons: ["OK", "Cancel"], accessory: field)
        return result == .alertFirstButtonReturn ? field.stringValue : nil
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo) async -> [URL]? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        guard let window = webView.window else { return nil }
        return await panel.beginSheetModal(for: window) == .OK ? panel.urls : nil
    }

    /// Sheet labelled with the frame's host so a page can't impersonate the browser.
    private func presentDialog(_ message: String, frame: WKFrameInfo, buttons: [String],
                               accessory: NSView? = nil) async -> NSApplication.ModalResponse {
        // After the first dialog the page gets a "no more dialogs" box, so alert loops can't lock the tab.
        guard let window = webView.window, !dialogsBlocked else { return .cancel }
        dialogsShown += 1
        let alert = NSAlert()
        alert.showsSuppressionButton = dialogsShown > 1
        alert.suppressionButton?.title = "Don’t allow more dialogs from this page"
        alert.messageText = frame.securityOrigin.host.isEmpty ? "This page says" : "\(frame.securityOrigin.host) says"
        alert.informativeText = message
        buttons.forEach { alert.addButton(withTitle: $0) }
        alert.accessoryView = accessory
        let result = await alert.beginSheetModal(for: window)
        if alert.suppressionButton?.state == .on { dialogsBlocked = true }
        return result
    }
}
