import AppKit
import WebKit

extension TabController {
    // MARK: WebTabDelegate — window services
    func webTab(_ page: WebTab, adoptCEFPopup child: CEFWebTab, url: String, background: Bool) -> Bool {
        host?.tabController(self, adoptCEFPopup: child, url: url, background: background) ?? false
    }
    func webTab(_ page: WebTab, didChangeThemeColor color: NSColor?) {
        if tab.themeColor != color { tab.themeColor = color }
    }
    func webTab(_ page: WebTab, didChangeSecureContent secure: Bool) {
        if tab.hasOnlySecureContent != secure { tab.hasOnlySecureContent = secure }
    }
    func webTab(_ page: WebTab, didDropFiles urls: [URL]) {
        (host as? BrowserCommands)?.openDroppedFiles(urls)
    }
    func webTab(_ page: WebTab, popupWith configuration: WKWebViewConfiguration, url: String,
                background: Bool) -> WKWebView? {
        host?.tabController(self, popupWith: configuration, url: url, background: background)
    }
    func webTab(_ page: WebTab, navigateToExtension url: String) { load(url) }
    func webTab(_ page: WebTab, openInNewTab url: String, background: Bool) {
        host?.tabController(self, openInNewTab: url, background: background)
    }
    func webTab(_ page: WebTab, requestsPermission request: PermissionRequest) {
        if let host { host.tabController(self, requestsPermission: request) } else { request.resolve(.deny) }
    }
    func webTab(_ page: WebTab, didFind found: Bool) {
        host?.tabController(self, didFind: found)
    }
}

// MARK: Status bar

extension TabController {
    func webTab(_ page: WebTab, didHoverLink url: String?) {
        guard page === self.page else { return }
        showLinkStatus(url)
    }

    /// Shows the hovered link's address over the page's bottom-left corner; nil hides it.
    func showLinkStatus(_ url: String?) {
        guard url != nil || linkStatus != nil else { return }
        let view = linkStatus ?? LinkStatusView()
        linkStatus = view
        if view.superview !== hostView || hostView.subviews.last !== view {
            hostView.addSubview(view, positioned: .above, relativeTo: nil)
        }
        view.show(url.map(Self.statusText), in: hostView)
    }

    /// The address exactly as the page gave it (never decoded: decoded text could imitate another address).
    static func statusText(_ url: String) -> String { String(url.prefix(512)) }
}
