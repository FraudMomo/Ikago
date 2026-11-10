import AppKit

/// Warnings and error pages: what a tab shows instead of a page it can't or shouldn't open.
extension TabController {
    func webTab(_ page: WebTab, willUpgradeToHTTPS url: URL) { upgradedURL = url }
    func webTab(_ page: WebTab, mayDownload url: URL?) async -> Bool {
        await DownloadPermissions.shared.mayDownload(pageURL: URL(string: page.currentURL), downloadURL: url, state: browserState, window: hostView.window ?? NSApp.mainWindow)
    }
    /// Stops a navigation to a likely phishing site. The warning replaces the page, so it also works in
    /// background tabs and can't be covered by the site.
    func webTab(_ page: WebTab, blocksUnsafeNavigation url: URL) -> Bool {
        guard let warning = SiteSafety.warning(for: url, state: browserState) else { return false }
        tab.loadError = warning.message
        failedURL = url.absoluteString
        tab.url = url.absoluteString
        let canGoBack = page.currentURL.hasPrefix("http") && tab.canGoBack
        present(ErrorPageView(url: url.absoluteString, message: warning.message, isDark: browserState?.isDark == true,
                              title: "This site may be trying to trick you", symbol: "exclamationmark.shield.fill",
                              retryTitle: canGoBack ? "Go Back" : warning.imitates.map { "Go to \($0)" } ?? "Close Tab",
                              secondaryTitle: "Continue Anyway",
                              onSecondary: { [weak self] in
                                  guard let self else { return }
                                  SiteSafety.allow(url.host ?? "", state: self.browserState)
                                  self.hideError()
                                  self.load(url.absoluteString)
                              }, onRetry: { [weak self] in
                                  guard let self else { return }
                                  self.hideError()
                                  if canGoBack { self.goBack() }
                                  else if let genuine = warning.imitates { self.load("https://" + genuine) }
                                  else { self.browserState?.closeTab(self.tab.id) }
                              }))
        return true
    }

    // MARK: Error page
    func showError(_ message: String) {
        present(ErrorPageView(url: tab.url, message: message, isDark: browserState?.isDark == true) { [weak self] in
            guard let self else { return }
            self.hideError()
            self.load(self.tab.url)
        })
    }
    /// HTTPS-only mode couldn't reach the site securely: say so, and let the person allow this one site.
    func showInsecureOption(_ url: URL, message: String) {
        let host = url.host ?? ""
        present(ErrorPageView(url: url.absoluteString,
                              message: "\(host) couldn’t be opened securely (\(message)) Over plain HTTP, others on your network could read or change what you see and send.",
                              isDark: browserState?.isDark == true, title: "This site isn’t available over HTTPS", symbol: "lock.slash",
                              secondaryTitle: "Open with HTTP and Remember This Site", onSecondary: { [weak self] in
                                  guard let self, let state = self.browserState else { return }
                                  let existing = state.browserPreferences.httpsExceptions ?? ""
                                  state.browserPreferences.httpsExceptions = existing.isEmpty ? host : existing + ", " + host
                                  BrowserSecurity.shared.apply(state.browserPreferences)
                                  self.upgradedURL = nil
                                  self.hideError()
                                  self.load(url.absoluteString)
                              }, onRetry: { [weak self] in
                                  guard let self else { return }
                                  self.hideError()
                                  self.load(url.absoluteString)
                              }))
    }
    func present(_ page: ErrorPageView) {
        hideError()
        let view = FileDropHostingView(rootView: page)
        view.registerForDraggedTypes([.fileURL])
        view.onFiles = { [weak self] in (self?.host as? BrowserCommands)?.openDroppedFiles($0) }
        view.sizingOptions = []
        view.identifier = PageWindowGrab.pageSurface
        view.frame = hostView.bounds
        view.autoresizingMask = [.width, .height]
        hostView.addSubview(view)
        errorView = view
        applyInset()
    }
    func hideError() {
        errorView?.removeFromSuperview()
        errorView = nil
        failedURL = nil
    }
}
