import AppKit
import WebKit

// What chrome.tabs / chrome.windows see: Ikago's real tabs and its window.

extension TabController: WKWebExtensionTab {
    func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        ExtensionManager.shared.browser
    }

    func indexInWindow(for context: WKWebExtensionContext) -> Int {
        ExtensionManager.shared.browser?.orderedTabControllers.firstIndex { $0 === self } ?? 0
    }

    func webView(for context: WKWebExtensionContext) -> WKWebView? { (page as? WebKitTab)?.webView }
    func title(for context: WKWebExtensionContext) -> String? { tab.title }
    func url(for context: WKWebExtensionContext) -> URL? { URL(string: tab.url).map { ExtensionManager.shared.resourceURL($0) } }
    func isLoadingComplete(for context: WKWebExtensionContext) -> Bool { !tab.isLoading }
    func isPinned(for context: WKWebExtensionContext) -> Bool { tab.pinned }
    func isMuted(for context: WKWebExtensionContext) -> Bool { tab.isMuted }
    func isSelected(for context: WKWebExtensionContext) -> Bool { isActive }
    func size(for context: WKWebExtensionContext) -> CGSize { hostView.bounds.size }
    func zoomFactor(for context: WKWebExtensionContext) -> Double { Double((page as? WebKitTab)?.webView.pageZoom ?? 1) }

    /// Clicking the page grants "activeTab"-style access, as in Chrome.
    func shouldGrantPermissionsOnUserGesture(for context: WKWebExtensionContext) -> Bool { true }

    func loadURL(_ url: URL, for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        load(url.absoluteString)
        completionHandler(nil)
    }

    func reload(fromOrigin: Bool, for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        if fromOrigin { page?.reloadIgnoringCache() } else { page?.reload() }
        completionHandler(nil)
    }

    func goBack(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        page?.goBack()
        completionHandler(nil)
    }

    func goForward(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        page?.goForward()
        completionHandler(nil)
    }

    func activate(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        selectInModel()
        completionHandler(nil)
    }

    func setSelected(_ selected: Bool, for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        if selected { selectInModel() }
        completionHandler(nil)
    }

    func setPinned(_ pinned: Bool, for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        if tab.pinned != pinned { togglePinInModel() }
        completionHandler(nil)
    }

    func setMuted(_ muted: Bool, for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        tab.isMuted = muted
        page?.setMuted(muted)
        ExtensionManager.shared.tabChanged(self, .muted)
        completionHandler(nil)
    }

    func setZoomFactor(_ zoomFactor: Double, for context: WKWebExtensionContext,
                       completionHandler: @escaping ((any Error)?) -> Void) {
        (page as? WebKitTab)?.webView.pageZoom = CGFloat(zoomFactor)
        completionHandler(nil)
    }

    func close(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        closeInModel()
        completionHandler(nil)
    }

    func takeSnapshot(using configuration: WKSnapshotConfiguration, for context: WKWebExtensionContext,
                      completionHandler: @escaping (NSImage?, (any Error)?) -> Void) {
        guard let webView = (page as? WebKitTab)?.webView else { return completionHandler(nil, ExtensionManager.error("Tab not loaded")) }
        webView.takeSnapshot(with: configuration) { image, error in completionHandler(image, error) }
    }
}

extension BrowserWindowController: WKWebExtensionWindow {
    /// The active Space's tabs in sidebar order: what "the window" holds for extensions.
    var orderedTabControllers: [TabController] {
        state.sidebarOrder.compactMap { content.controller(for: $0.id) }
    }

    func tabs(for context: WKWebExtensionContext) -> [any WKWebExtensionTab] { orderedTabControllers }
    func activeTab(for context: WKWebExtensionContext) -> (any WKWebExtensionTab)? { activeController }
    func windowType(for context: WKWebExtensionContext) -> WKWebExtension.WindowType { .normal }
    func isPrivate(for context: WKWebExtensionContext) -> Bool { false }

    func windowState(for context: WKWebExtensionContext) -> WKWebExtension.WindowState {
        guard let window else { return .normal }
        if window.isInFullScreen { return .fullscreen }
        if window.isMiniaturized { return .minimized }
        return window.isZoomed ? .maximized : .normal
    }

    func frame(for context: WKWebExtensionContext) -> CGRect { window?.frame ?? .zero }
    func screenFrame(for context: WKWebExtensionContext) -> CGRect { window?.screen?.frame ?? .zero }

    func focus(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        window?.makeKeyAndOrderFront(nil)
        completionHandler(nil)
    }

    func setFrame(_ frame: CGRect, for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        window?.setFrame(frame, display: true)
        completionHandler(nil)
    }

    func close(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        window?.performClose(nil)
        completionHandler(nil)
    }

    /// Opens a tab for an extension (tabs.create, options page) and returns it right away.
    @discardableResult
    func openTabForExtension(url: String, active: Bool, pinned: Bool, useNewTabPosition: Bool = false) -> TabController? {
        guard let tab = state.newTab(url: url, select: active, after: useNewTabPosition ? nil : state.activeTabID) else { return nil }
        if pinned { state.togglePin(tab.id) }
        return content.ensureController(for: tab)
    }
}

// MARK: - Tell the extension controllers what happened

extension ExtensionManager {
    // Private windows are invisible to extensions: their tabs and windows are never reported.
    func tabOpened(_ tab: TabController) {
        guard !tab.isPrivate else { return }
        allControllers.forEach { $0.didOpenTab(tab) }
    }
    func tabClosed(_ tab: TabController) {
        guard !tab.isPrivate else { return }
        allControllers.forEach { $0.didCloseTab(tab, windowIsClosing: false) }
    }

    func tabActivated(_ tab: TabController, previous: TabController?) {
        guard !tab.isPrivate else { return }
        allControllers.forEach { $0.didActivateTab(tab, previousActiveTab: previous) }
    }

    func tabChanged(_ tab: TabController, _ properties: WKWebExtension.TabChangedProperties) {
        guard !tab.isPrivate else { return }
        allControllers.forEach { $0.didChangeTabProperties(properties, for: tab) }
    }

    func windowOpened(_ window: BrowserWindowController) {
        guard !window.state.isPrivate else { return }
        allControllers.forEach { $0.didOpenWindow(window) }
    }
    func windowFocused(_ window: BrowserWindowController?) {
        guard window?.state.isPrivate != true, window !== focusedWindow else { return }
        focusedWindow = window
        allControllers.forEach { $0.didFocusWindow(window) }
    }
}
