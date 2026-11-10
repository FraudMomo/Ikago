import AppKit
import SwiftUI
import WebKit

/// Services a tab needs from its window (popups, prompts, find results).
@MainActor
protocol TabHost: AnyObject {
    func tabController(_ tab: TabController, adoptCEFPopup page: CEFWebTab, url: String, background: Bool) -> Bool
    func tabController(_ tab: TabController, popupWith configuration: WKWebViewConfiguration,
                       url: String, background: Bool) -> WKWebView?
    func tabController(_ tab: TabController, openInNewTab url: String, background: Bool)
    func tabController(_ tab: TabController, requestsPermission request: PermissionRequest)
    func tabController(_ tab: TabController, didFind found: Bool)
    func tabControllerDidClose(_ tab: TabController)
    /// The user started dragging this pane's header (shows the split drop zones).
    func tabControllerEndedDrag(_ tab: TabController)
    func tabControllerBeganDrag(_ tab: TabController)
}

/// Owns one tab's page (WebTab) and its host view, and forwards page events into the
/// `TabItem` / `BrowserState` model.
@MainActor
final class TabController: NSObject, WebTabDelegate {
    let tab: TabItem
    let hostView = TabHostView()
    /// Behind the web view: the floating island's reflection of the page's top.
    private let reflection = ReflectionView()
    /// Split view: strip over the pane on hover (move, remove from split).
    private(set) var header: PaneHeaderView?
    private var reflectionTask: Task<Void, Never>?
    weak var host: TabHost?
    private weak var state: BrowserState?
    var browserState: BrowserState? { state }
    private(set) var page: WebTab?
    var isClosing = false
    /// Opened by another page (window.open / target=_blank): keeps its engine, so window.opener keeps working.
    let isPopup: Bool
    /// Per-site engines: the pages before and after an engine switch (`TabController+Engines`).
    var handoff = EngineHandoff()
    var engineBadge: NSView?
    /// The hovered link's address (`LinkStatusView`), created on the first hover.
    var linkStatus: LinkStatusView?
    var errorView: NSView?
    /// A Ikago page (Settings, History, Downloads) shown instead of a web view.
    private var internalView: NSView?
    /// The address that failed, kept while the error page shows.
    var failedURL: String?
    /// The HTTP address HTTPS-only mode just upgraded, so a failure can offer to open it anyway.
    var upgradedURL: URL?
    /// Space at the top the floating island covers (see `BrowserState.floatingContentInset`).
    var topInset: CGFloat = 0 {
        didSet { if topInset != oldValue { applyInset() } }
    }
    /// `page` is set for popups, whose web view WebKit needs immediately.
    init(tab: TabItem, state: BrowserState, host: TabHost, page: WebTab? = nil) {
        self.tab = tab
        self.state = state
        self.host = host
        isPopup = page != nil
        super.init()
        hostView.addSubview(reflection)
        hostView.onHover = { [weak self] inside in self?.setHeaderVisible(inside) }
        if let page { attach(page) }
    }
    var isStarted: Bool { page != nil || internalView != nil }
    var isActive: Bool { state?.visibleTabIDs.contains(tab.id) == true }
    var profileID: String {
        if let state, state.isPrivate { return state.privateProfileID }
        return state?.spaces.first { $0.id == tab.spaceID }?.profileID ?? "Default"
    }
    var isPrivate: Bool { state?.isPrivate == true }
    /// Lazily creates the page the first time the tab is shown. Extension pages (options,
    /// tabs.create with an extension URL) must use their extension's configuration.
    func startIfNeeded() {
        guard page == nil, internalView == nil, !isClosing else { return }
        if let builtIn = InternalPage(url: tab.url) { tab.isHibernating = false; return showInternal(builtIn) }
        // Attaching a fresh WKWebView can publish its initial about:blank URL through KVO.
        // Keep the requested destination before attaching, rather than reading the live model again.
        let destination = tab.url
        let url = URL(string: destination)
        let engine = targetEngine(for: destination)
        let extensionContext = engine == .webkit ? url.flatMap { ExtensionManager.shared.context(for: $0) } : nil
        if ExtensionURL.isExtension(tab.url), extensionContext == nil, engine == .webkit {
            tab.loadError = "This extension is unavailable. Enable or reinstall it in Settings ▸ Extensions."
            showError(tab.loadError!)
            return
        }
        let page: any WebTab
        do { page = try makePage(engine, extensionContext: extensionContext) } catch { showError(error.localizedDescription); return }
        attach(page)
        // Chromium loads extension pages (a new-tab page such as Momentum) in an ordinary page.
        let chromiumExtensionPage = engine == .chromium && ExtensionURL.isExtension(destination)
        if AddressResolver.isPageURL(destination) || extensionContext != nil || chromiumExtensionPage, let url {
            page.load(chromiumExtensionPage ? destination : ExtensionManager.shared.resourceURL(url).absoluteString)
        }
    }
    func selectInModel() { state?.select(tab.id) }
    func togglePinInModel() { state?.togglePin(tab.id); ExtensionManager.shared.tabChanged(self, .pinned) }
    func closeInModel() { state?.closeTab(tab.id) }
    func attach(_ page: WebTab) {
        tab.playback = MediaPlaybackState()
        tab.isHibernating = false
        tab.engine = page.engine
        self.page = page
        page.setTopInset(topInset)
        page.setMuted(tab.isMuted)
        page.delegate = self
        page.contentView.frame = hostView.bounds
        hostView.addSubview(page.contentView)
    }
    func load(_ url: String) {
        tab.url = url
        tab.loadError = nil
        if let builtIn = InternalPage(url: url) {
            page?.tearDown()
            page = nil
            tearDownParked()
            return showInternal(builtIn)
        }
        if internalView != nil {
            internalView?.removeFromSuperview()
            internalView = nil
            tab.title = ""
        }
        // A site another engine opens (per-site engines): reopen the tab there.
        if let page, Self.isWebsite(url), targetEngine(for: url) != page.engine {
            return switchEngine(to: targetEngine(for: url), url: url)
        }
        // An extension's page (e.g. a new-tab page) runs in the extension's own web view
        // setup, which won't show websites: leaving it for a site needs a normal page.
        if let page, page.engine == .webkit {
            let current = URL(string: page.currentURL).flatMap { ExtensionManager.shared.context(for: $0) }
            let destination = URL(string: url).flatMap { ExtensionManager.shared.context(for: $0) }
            if current !== destination, current != nil || destination != nil {
                page.tearDown()
                self.page = nil
            }
        }
        if let page { page.load(URL(string: url).map { ExtensionManager.shared.resourceURL($0).absoluteString } ?? url) } else { startIfNeeded() }
    }
    func refreshSplitHeader() {
        guard let window = hostView.window else { return }
        let point = hostView.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        setHeaderVisible(hostView.bounds.contains(point))
    }
    func setHeaderVisible(_ visible: Bool) {
        guard let state else { return }
        guard visible, state.splitGroup(of: tab.id) != nil else { header?.isHidden = true; return }
        if header == nil {
            let view = PaneHeaderView(tab: tab)
            view.onRemove = { [weak self] in
                guard let self, let state = self.state else { return }
                self.header?.isHidden = true
                if self.tab.url == InternalPage.splitEmpty.url { state.closeTab(self.tab.id) }
                else { state.separate(self.tab.id) }
            }
            view.onDragBegan = { [weak self] in
                guard let self else { return }; self.host?.tabControllerBeganDrag(self)
            }
            view.onDragEnded = { [weak self] in
                guard let self else { return }; self.host?.tabControllerEndedDrag(self)
            }
            header = view
            header?.autoresizingMask = [.width, .minYMargin]
        }
        guard let header else { return }
        header.handle.title.stringValue = tab.displayTitle
        header.frame = NSRect(x: 10, y: hostView.bounds.height - topInset - 34, width: max(0, hostView.bounds.width - 20), height: 26)
        hostView.addSubview(header, positioned: .above, relativeTo: nil)  // above the page and any internal view
        header.isHidden = false
    }
    func applyInset() {
        page?.setTopInset(topInset)
        let insets = NSEdgeInsets(top: topInset, left: 0, bottom: 0, right: 0)
        internalView?.additionalSafeAreaInsets = insets
        errorView?.additionalSafeAreaInsets = insets
        reflection.frame = NSRect(x: 0, y: hostView.bounds.height - topInset, width: hostView.bounds.width, height: topInset)
        if topInset > 0 { refreshReflection() } else { reflection.clear() }
    }
    /// Re-copies the top of the page into the reflection (after a load, or when the inset changes).
    /// Debounced and cancellable: dragging a size slider changes the inset many times a second.
    private func refreshReflection(after delay: Duration = .milliseconds(200)) {
        guard topInset > 0, page != nil else { return reflection.clear() }
        reflectionTask?.cancel()
        reflectionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, self.topInset > 0, let page = self.page else { return }
            page.snapshotBelowInset(self.topInset) { [weak self] image in self?.reflection.show(image) }
        }
    }
    private func showInternal(_ builtIn: InternalPage) {
        tab.playback = MediaPlaybackState(); tab.isPlayingAudio = false
        internalView?.removeFromSuperview()
        guard let state else { return }
        let view = FileDropHostingView(rootView: InternalPageView(page: builtIn, state: state,
                                                            commands: host as? BrowserCommands, tabID: tab.id))
        view.registerForDraggedTypes([.fileURL])
        view.onFiles = { [weak self] in (self?.host as? BrowserCommands)?.openDroppedFiles($0) }
        view.sizingOptions = []
        view.identifier = PageWindowGrab.pageSurface
        view.frame = hostView.bounds
        view.autoresizingMask = [.width, .height]
        hostView.addSubview(view)
        internalView = view
        applyInset()
        tab.title = builtIn.title
        tab.isLoading = false
        tab.canGoBack = false
        tab.canGoForward = false
    }
    func focus() { page?.focus() }
    func hibernate() {
        guard !isActive, isStarted else { return }
        reflectionTask?.cancel()
        reflection.clear()
        page?.delegate = nil
        page?.tearDown()
        page = nil
        tearDownParked()
        hideError()
        internalView?.removeFromSuperview()
        internalView = nil
        tab.isLoading = false
        tab.isPlayingAudio = false
        tab.playback = MediaPlaybackState()
        tab.cameraActive = false
        tab.microphoneActive = false
        tab.cameraMuted = false
        tab.microphoneMuted = false
        tab.isHibernating = true
        tab.canGoBack = false
        tab.canGoForward = false
    }
    func close() {
        isClosing = true
        page?.tearDown()
        page = nil
        tearDownParked()
        hostView.removeFromSuperview()
        host?.tabControllerDidClose(self)
    }
    // MARK: WebTabDelegate — display / load
    func webTab(_ page: WebTab, didChangeTitle title: String) {
        state?.updateTitle(tabID: tab.id, title: title)
        ExtensionManager.shared.tabChanged(self, .title)
    }
    func webTab(_ page: WebTab, didChangeURL url: String) {
        guard !url.isEmpty, failedURL == nil else { return }
        tab.url = ExtensionManager.shared.canonicalURL(url)
        ExtensionManager.shared.tabChanged(self, .URL)
    }
    func webTab(_ page: WebTab, didCommit url: String) {
        showLinkStatus(nil)
        reflection.clear()
        upgradedURL = nil
        state?.recordVisit(tabID: tab.id, url: url)
    }
    func webTab(_ page: WebTab, didChangeProgress progress: Double) {
        if tab.progress != progress { tab.progress = progress }
    }
    func webTab(_ page: WebTab, didChangeLoading isLoading: Bool, canGoBack: Bool, canGoForward: Bool) {
        if tab.isLoading != isLoading { tab.isLoading = isLoading }
        handoff.pageCanGoBack = canGoBack
        handoff.pageCanGoForward = canGoForward
        refreshHistoryButtons()
        if isLoading {
            if tab.loadError != nil { tab.loadError = nil }
            hideError()
        } else {
            if tab.progress != 1 { tab.progress = 1 }
            // Give the page a moment to paint before copying its top.
            refreshReflection(after: .milliseconds(700))
        }
        ExtensionManager.shared.tabChanged(self, .loading)
    }
    func webTab(_ page: WebTab, didFailLoad message: String, url: String?) {
        if tab.loadError != message { tab.loadError = message }
        if let url { failedURL = url; tab.url = url }
        if let upgraded = upgradedURL, url.flatMap(URL.init(string:))?.host == upgraded.host { return showInsecureOption(upgraded, message: message) }
        showError(message)
    }
    func webTab(_ page: WebTab, didChangeMedia audible: Bool, camera: WKMediaCaptureState, microphone: WKMediaCaptureState) {
        guard tab.isPlayingAudio != audible || tab.cameraActive != (camera != .none) || tab.cameraMuted != (camera == .muted)
                || tab.microphoneActive != (microphone != .none) || tab.microphoneMuted != (microphone == .muted) else { return }
        let audioChanged = tab.isPlayingAudio != audible
        tab.isPlayingAudio = audible
        // A muted capture still holds the device (macOS keeps its indicator on), so it counts as in use.
        tab.cameraActive = camera != .none
        tab.cameraMuted = camera == .muted
        tab.microphoneActive = microphone != .none
        tab.microphoneMuted = microphone == .muted
        if audioChanged { ExtensionManager.shared.tabChanged(self, .playingAudio) }
    }
    /// window.close(): close the tab through the model, like the user would.
    func webTabDidClose(_ page: WebTab) {
        state?.closeTab(tab.id)
    }
}

