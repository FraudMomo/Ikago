import AppKit
import WebKit
import IKCEFBridge

@MainActor
final class CEFWebTab: WebTab {
    let page: IKCEFPage
    private let dock: DevToolsDock
    var engine: BrowserEngine { .chromium }
    var contentView: NSView { page }
    weak var delegate: WebTabDelegate?
    private(set) var currentURL = "about:blank"
    var isLoading: Bool { page.loading }
    var isAudible = false
    var playback = MediaPlaybackState()
    var lastMediaReports: [[String: Any]] = []
    var cameraActive = false
    var microphoneActive = false
    var isMuted: Bool { page.audioMuted }
    var documentGeneration = 0
    var isTornDown = false
    let profileID: String
    var stateTask: Task<Void, Never>?
    /// The theme color the state poll last reported, so an unchanged one isn't sent again.
    var lastPolledThemeColor: NSColor?
    /// The "ikago-browser" isolated world of the current document, reused by `evaluate`.
    var browserWorld: (generation: Int, context: Int)?
    /// Whether this document has the password key, and its isolated world.
    var passwordKeyState = PasswordKeyState()
    private var externalLinks = ExternalLinkOpener()
    /// H.264/AAC videos Chromium can't play, played by macOS over the page.
    lazy var nativeVideo = NativeVideoOverlay(tab: self)
    /// "Add to Ikago" on the Chrome Web Store.
    private lazy var storeBridge = ChromiumStoreBridge(tab: self)
    /// A page's element fullscreen (YouTube's fullscreen button).
    private lazy var fullscreen = ChromiumFullscreen(page: page)
    var zoomLevel: Double {
        get { page.zoomLevel }
        set { page.zoomLevel = min(9, max(-7, newValue)) }
    }
    var isInspectorVisible: Bool { page.devToolsVisible }
    init(profileID: String, adopting: IKCEFPage? = nil) throws {
        self.profileID = profileID
        try CEFSessions.prepare(profileID)
        page = try adopting ?? IKCEFPage.make(profile: profileID)
        dock = DevToolsDock(page: page)
        page.devToolsWindowHandler = { [weak self] window in self?.dock.attach(window) }
        if !page.ready { page.documentStartScript = MediaTranslation.documentStartScript }
        dock.close = { [weak page] in page?.toggleDevTools() }
        page.eventHandler = { [weak self] name, payload in
            MainActor.assumeIsolated { self?.receive(name, payload) }
        }
        page.mediaPermissionHandler = { [weak self] native in
            MainActor.assumeIsolated {
                guard let self, !self.isTornDown, let delegate = self.delegate else { native.resolve(false); return }
                var kinds: PermissionRequest.Kinds = []
                if native.camera { kinds.insert(.camera) }
                if native.microphone { kinds.insert(.microphone) }
                let request = PermissionRequest(origin: native.origin, kinds: kinds) { decision in
                    native.resolve(decision == .grant)
                }
                native.cancellationHandler = { [weak request] in
                    MainActor.assumeIsolated { request?.invalidate() }
                }
                delegate.webTab(self, requestsPermission: request)
            }
        }
        page.externalLinkHandler = { [weak self] url, host in
            Task { @MainActor [weak self] in
                guard let self, !self.isTornDown else { return }
                await self.externalLinks.open(url, sourceHost: host, in: self.page.window)
            }
        }
        page.navigationHandler = { [weak self] url, method in
            MainActor.assumeIsolated {
                guard let self else { return false }
                if self.delegate?.webTab(self, blocksUnsafeNavigation: url) == true { return false }
                if self.delegate?.webTab(self, handsOff: url, method: method) == true { return false }
                guard BrowserSecurity.shared.requiresHTTPS(url) else { return true }
                if method == "GET", let secure = BrowserSecurity.secureURL(url) {
                    self.delegate?.webTab(self, willUpgradeToHTTPS: url)
                    // Skip the upgrade if something else navigated the page meanwhile.
                    let generation = self.documentGeneration
                    DispatchQueue.main.async { [weak self] in
                        MainActor.assumeIsolated {
                            guard let self, !self.isTornDown, self.documentGeneration == generation else { return }
                            self.load(secure.absoluteString)
                        }
                    }
                } else { self.delegate?.webTab(self, didFailLoad: "HTTPS-only mode blocked an insecure form submission.", url: url.absoluteString) }
                return false
            }
        }
        page.downloadGateHandler = { [weak self] _, download, reply in
            MainActor.assumeIsolated {
                guard let self, let delegate = self.delegate else { return reply(false) }
                Task { @MainActor in reply(await delegate.webTab(self, mayDownload: URL(string: download))) }
            }
        }
        page.popupHandler = { [weak self] native, url, background in
            MainActor.assumeIsolated {
                guard let self, let delegate = self.delegate,
                      let child = try? CEFWebTab(profileID: self.profileID, adopting: native) else { return false }
                let accepted = delegate.webTab(self, adoptCEFPopup: child, url: url, background: background)
                if !accepted { child.tearDown() }
                return accepted
            }
        }
        setDeveloperTools(WebProfiles.developerTools)
        observePageState()
    }
    func load(_ url: String) { documentGeneration += 1; page.loadURL(url) }
    func visibilityChanged() {
        guard !isTornDown else { return }
        if isPageShown { observePageState() }
        nativeVideo.visibilityChanged()
    }
    func goBack() { page.goBack() }
    func goForward() { page.goForward() }
    func reload() { page.reloadIgnoringCache(false) }
    func reloadIgnoringCache() { page.reloadIgnoringCache(true) }
    func stopLoading() { page.stopLoading() }
    func focus() { page.focus() }
    func tearDown() {
        guard !isTornDown else { return }
        isTornDown = true; documentGeneration += 1
        stateTask?.cancel(); stateTask = nil
        removePasswordMonitor()
        nativeVideo.tearDown()
        storeBridge.tearDown()
        fullscreen.tearDown()
        delegate = nil
        page.eventHandler = nil; page.externalLinkHandler = nil; page.popupHandler = nil; page.navigationHandler = nil; page.downloadGateHandler = nil
        page.mediaPermissionHandler = nil
        page.close(); page.removeFromSuperview()
    }
    /// After full screen comes or goes (see `IKCEFPage.refitPage`).
    func refitPage() { page.refit() }
    func setTopInset(_ inset: CGFloat) {
        // While a video has the whole screen the page has no inset; keep the tab's latest for afterwards.
        if fullscreen.isActive { fullscreen.pendingInset = inset } else { page.topInset = inset }
    }
    func snapshotBelowInset(_ inset: CGFloat, completion: @escaping (NSImage?) -> Void) {
        guard inset > 0 else { completion(nil); return }
        Task { @MainActor in completion(try? await snapshot(rect: NSRect(x: 0, y: 0, width: page.bounds.width, height: inset))) }
    }
    func find(_ text: String, forward: Bool, matchCase: Bool) { page.findText(text, forward: forward, matchCase: matchCase) }
    func clearFindSelection() { page.clearFind() }
    func stopCapture(camera: Bool, microphone: Bool) {
        if camera || microphone { page.stopCaptureAndReload() }
    }
    // CEF exposes playback mute, but no public per-device capture mute API.
    // The CEF capture menu offers the explicit stop-and-reload action instead.
    func setCaptureMuted(_ muted: Bool, microphone: Bool) { }
    func setMuted(_ muted: Bool) {
        page.audioMuted = muted
        nativeVideo.setTabMuted(muted)
        if muted { isAudible = false; reportMedia() }
        observePageState()
    }
    func printPage() { page.printPage() }
    func setDeveloperTools(_ enabled: Bool) { page.setDeveloperToolsEnabled(enabled) }
    func toggleInspector() { page.toggleDevTools() }
    private func receive(_ name: String, _ payload: [AnyHashable: Any]) {
        guard !isTornDown else { return }
        let text = payload["value"] as? String ?? ""
        switch name {
        case "navigation": documentGeneration += 1
        case "capture":
            cameraActive = payload["camera"] as? Bool ?? false
            microphoneActive = payload["microphone"] as? Bool ?? false
            reportMedia()
        case "title": delegate?.webTab(self, didChangeTitle: text)
        case "status": delegate?.webTab(self, didHoverLink: text.isEmpty ? nil : text)
        case "fullscreen": fullscreen.pageChanged(fullscreen: payload["value"] as? Bool ?? false)
        case "url": currentURL = text; delegate?.webTab(self, didChangeURL: text); storeBridge.pageChanged()
        case "commit":
            documentGeneration += 1; currentURL = text
            updatePlayback([])
            observePageState()
            injectPasswordKey()
            nativeVideo.documentChanged()
            delegate?.webTab(self, didChangeSecureContent: false)
            delegate?.webTab(self, didCommit: text)
        case "progress": delegate?.webTab(self, didChangeProgress: payload["value"] as? Double ?? 0)
        case "loading":
            if !page.loading { injectPasswordKey(); nativeVideo.inject(); storeBridge.pageChanged() }
            delegate?.webTab(self, didChangeLoading: page.loading, canGoBack: page.canGoBack, canGoForward: page.canGoForward)
        case "favicon": delegate?.webTab(self, didFindFavicon: URL(string: text))
        case "security": delegate?.webTab(self, didChangeSecureContent: payload["value"] as? Bool ?? false)
        case "theme":
            let argb = (payload["value"] as? NSNumber)?.uint32Value ?? 0
            delegate?.webTab(self, didChangeThemeColor: NSColor(srgbRed: Double((argb >> 16) & 255)/255,
                green: Double((argb >> 8) & 255)/255, blue: Double(argb & 255)/255, alpha: Double(argb >> 24)/255))
        case "failure": delegate?.webTab(self, didFailLoad: "The page could not load (CEF error \(payload["code"] ?? 0)).", url: payload["url"] as? String)
        case "find": delegate?.webTab(self, didFind: payload["found"] as? Bool ?? false)
        case "closed": delegate?.webTabDidClose(self)
        case "crash":
            passwordKeyState.context = nil; passwordKeyState.injectedGeneration = -1
            delegate?.webTab(self, didFailLoad: "The Chromium page process stopped. Reload to try again.", url: currentURL)
        default: break
        }
    }
}
