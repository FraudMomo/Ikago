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
    func tabController(_ tab: TabController, didFind result: FindResult)
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
    /// Split view: strip over the pane on hover (move, remove from split).
    private(set) var header: PaneHeaderView?
    weak var host: TabHost?
    private weak var state: BrowserState?
    var browserState: BrowserState? { state }
    /// Set by `attach`, cleared on close or when the tab moves to another window (`releasePage`).
    var page: WebTab?
    var isClosing = false
    /// Opened by another page (window.open / target=_blank): keeps its engine, so window.opener keeps working.
    let isPopup: Bool
    /// Per-site engines: the pages before and after an engine switch (`TabController+Engines`).
    var handoff = EngineHandoff()
    var engineBadge: NSView?
    /// The hovered link's address (`LinkStatusView`), created on the first hover.
    var linkStatus: LinkStatusView?
    /// Find in page's marks along the page's edge (WebKit).
    var findTicks: FindTicksView?
    var errorView: NSView?
    /// Reader mode over this page (`ReaderOverlay`).
    var reader: ReaderOverlay?
    /// The page's translation, while it is shown translated (`PageTranslation`).
    var translation: PageTranslation?
    /// A Ikago page (Settings, History, Downloads) shown instead of a web view.
    private var internalView: NSView?
    /// The address that failed, kept while the error page shows.
    var failedURL: String?
    /// The HTTP address HTTPS-only mode just upgraded, so a failure can offer to open it anyway.
    var upgradedURL: URL?
    /// `page` is set for popups, whose web view WebKit needs immediately, and for tabs moved in from another window.
    init(tab: TabItem, state: BrowserState, host: TabHost, page: WebTab? = nil, popup: Bool? = nil) {
        self.tab = tab
        self.state = state
        self.host = host
        isPopup = popup ?? (page != nil)
        super.init()
        hostView.onHover = { [weak self] inside in if !inside { self?.setHeaderVisible(false) } }
        hostView.onMove = { [weak self] point in self?.pointerMoved(to: point) }
        if let page { attach(page) }
    }
    var isStarted: Bool { page != nil || internalView != nil }
    var isActive: Bool { state?.visibleTabIDs.contains(tab.id) == true || (host as? BrowserWindowController)?.peekController === self }
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
        if restoreHistory(into: page, destination: destination) { return }  // the page brought back its saved history (and its page)
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
        tab.hasLivePage = true
        self.page = page
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
        tab.hasLivePage = false
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
                tab.hasLivePage = false
            }
        }
        if let page { page.load(URL(string: url).map { ExtensionManager.shared.resourceURL($0).absoluteString } ?? url) } else { startIfNeeded() }
    }
    func refreshSplitHeader() {
        guard let window = hostView.window else { return }
        let point = hostView.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        pointerMoved(to: point)
    }
    /// The header shows while the pointer is near the pane's top edge (or on the header itself), and fades away otherwise.
    private func pointerMoved(to point: NSPoint) {
        let band = PaneHeaderView.topGap + PaneHeaderView.height + 22
        let nearTop = hostView.bounds.contains(point) && point.y >= hostView.bounds.height - band
        setHeaderVisible(nearTop)
    }
    func setHeaderVisible(_ visible: Bool) {
        guard let state else { return }
        guard visible, state.splitGroup(of: tab.id) != nil else { fadeHeader(in: false); return }
        if header == nil {
            let view = PaneHeaderView(tab: tab)
            view.onRemove = { [weak self] in
                guard let self, let state = self.state else { return }
                self.fadeHeader(in: false)
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
        }
        guard let header else { return }
        header.handle.title.stringValue = tab.displayTitle
        let width = header.preferredWidth(in: hostView.bounds.width)
        header.frame = NSRect(x: ((hostView.bounds.width - width) / 2).rounded(),
                              y: hostView.bounds.height - PaneHeaderView.topGap - PaneHeaderView.height,
                              width: width, height: PaneHeaderView.height)
        header.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin]
        if header.superview !== hostView || hostView.subviews.last !== header {
            hostView.addSubview(header, positioned: .above, relativeTo: nil)  // above the page and any internal view
        }
        fadeHeader(in: true)
    }

    private func fadeHeader(in visible: Bool) {
        guard let header else { return }
        if visible { header.isHidden = false }
        guard header.alphaValue != (visible ? 1 : 0) || (!visible && !header.isHidden) else { return }
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduce ? 0 : visible ? 0.14 : 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            header.animator().alphaValue = visible ? 1 : 0
        } completionHandler: { [weak header] in
            MainActor.assumeIsolated { if let header, header.alphaValue == 0 { header.isHidden = true } }
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
        tab.title = builtIn.title
        tab.isLoading = false
        tab.canGoBack = false
        tab.canGoForward = false
    }
    func focus() { page?.focus() }
    func hibernate() {
        guard !isActive, isStarted else { return }
        page?.delegate = nil
        page?.tearDown()
        page = nil
        tab.hasLivePage = false
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
        tab.hasLivePage = false
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
        closeReader()
        translation = nil
        upgradedURL = nil
        state?.recordVisit(tabID: tab.id, url: url)
        ExtensionAccessPresenter.shared.pageCommitted(url, engine: tab.engine ?? BrowserRuntime.engine, in: self)
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
            captureHistory()
            if tab.progress != 1 { tab.progress = 1 }
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
