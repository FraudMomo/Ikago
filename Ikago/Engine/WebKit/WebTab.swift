import AppKit
import WebKit

/// One page: a WKWebView plus the state and commands the browser needs from it.
/// Navigation, UI and download handling live in WebKitTab+Delegates.swift.
@MainActor
final class WebKitTab: NSObject, WebTab {
    var engine: BrowserEngine { .webkit }
    var contentView: NSView { webView }
    let webView: WKWebView
    weak var delegate: WebTabDelegate?
    var externalLinks = ExternalLinkOpener()
    var httpsUpgradeAttempts = 0
    /// Dialog throttling and crash-loop state (WebKitTab+Safety.swift); reset on each page commit.
    var dialogsShown = 0
    var dialogsBlocked = false
    var lastCrash: Date?
    private var observations: [NSKeyValueObservation] = []
    private struct LoadingState: Equatable { var isLoading, canGoBack, canGoForward: Bool }
    private var reportedLoading: LoadingState?
    private(set) var isMuted = false
    /// Latest audible report per frame (keyed by the frame's URL), with the frame to mute.
    var audibleFrames: [String: (audible: Bool, frame: WKFrameInfo, playback: MediaPlaybackState)] = [:]
    private(set) var isAudible = false

    /// A fresh page in `profileID`'s storage.
    convenience init(profileID: String) {
        self.init(configuration: WebProfiles.configuration(for: profileID))
    }

    /// A page for an existing configuration (popups must use WebKit's).
    init(configuration: WKWebViewConfiguration) {
        let view = FileDropWebView(frame: .zero, configuration: configuration)
        webView = view
        super.init()
        view.onFiles = { [weak self] urls in
            guard let self else { return }
            self.delegate?.webTab(self, didDropFiles: urls)
        }
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        setDeveloperTools(WebProfiles.developerTools)
        webView.autoresizingMask = [.width, .height]
        observe()
        MediaMonitor.shared.register(self)
        LinkHoverMonitor.shared.register(self)
        BrowserSecurity.shared.register(self)
    }

    private func observe() {
        func on<V>(_ path: KeyPath<WKWebView, V>, _ body: @escaping @MainActor (WebKitTab) -> Void) {
            observations.append(webView.observe(path, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated { if let self { body(self) } }  // WKWebView KVO fires on main
            })
        }
        on(\.title) { $0.delegate?.webTab($0, didChangeTitle: $0.webView.title ?? "") }
        on(\.url) { $0.delegate?.webTab($0, didChangeURL: $0.currentURL) }
        on(\.estimatedProgress) { $0.delegate?.webTab($0, didChangeProgress: $0.webView.estimatedProgress) }
        on(\.themeColor) { $0.delegate?.webTab($0, didChangeThemeColor: $0.webView.themeColor) }
        on(\.hasOnlySecureContent) { $0.delegate?.webTab($0, didChangeSecureContent: $0.webView.hasOnlySecureContent) }
        on(\.isLoading) { $0.reportLoading() }
        on(\.canGoBack) { $0.reportLoading() }
        on(\.canGoForward) { $0.reportLoading() }
        on(\.cameraCaptureState) { $0.reportMedia() }
        on(\.microphoneCaptureState) { $0.reportMedia() }
    }

    /// Page content starts `inset` below the top (the floating island); it scrolls under it.
    func setTopInset(_ inset: CGFloat) {
        webView.obscuredContentInsets = NSEdgeInsets(top: inset, left: 0, bottom: 0, right: 0)
    }

    /// The `inset` points of page just under the top inset, for the floating island's reflection.
    func snapshotBelowInset(_ inset: CGFloat, completion: @escaping (NSImage?) -> Void) {
        guard inset > 0, webView.bounds.height > inset * 2 else { return completion(nil) }
        let config = WKSnapshotConfiguration()
        config.rect = CGRect(x: 0, y: inset, width: webView.bounds.width, height: inset)
        webView.takeSnapshot(with: config) { image, _ in completion(image) }
    }

    // MARK: Media state

    func frameReportedAudio(_ audible: Bool, playback: MediaPlaybackState, frame: WKFrameInfo) {
        audibleFrames[frame.request.url?.absoluteString ?? ""] = (audible, frame, playback)
        if isMuted { applyMute() }
        reportMedia()
    }

    /// A new page in the main frame: its old frames are gone.
    func resetMedia() {
        audibleFrames.removeAll()
        reportMedia()
    }

    private func reportMedia() {
        isAudible = audibleFrames.values.contains { $0.audible }
        let playback = audibleFrames.values.first { $0.playback.available && $0.playback.playing }?.playback
            ?? audibleFrames.values.first { $0.playback.available }?.playback ?? MediaPlaybackState()
        delegate?.webTab(self, didChangePlayback: playback)
        delegate?.webTab(self, didChangeMedia: isAudible, camera: webView.cameraCaptureState,
                         microphone: webView.microphoneCaptureState)
    }

    /// One report per change: isLoading, canGoBack and canGoForward often change together, and each
    /// report reaches the extensions.
    func reportLoading() {
        guard let delegate else { return }
        let current = LoadingState(isLoading: webView.isLoading, canGoBack: webView.canGoBack, canGoForward: webView.canGoForward)
        guard current != reportedLoading else { return }
        reportedLoading = current
        delegate.webTab(self, didChangeLoading: current.isLoading, canGoBack: current.canGoBack, canGoForward: current.canGoForward)
    }

    var currentURL: String { webView.url?.absoluteString ?? "" }
    var isLoading: Bool { webView.isLoading }

    // MARK: Navigation

    func load(_ url: String) {
        httpsUpgradeAttempts = 0
        guard let target = URL(string: url) else { return }
        if target.isFileURL {
            guard AddressResolver.isLocalFileURL(url) else { return }
            // Permit sibling styles, scripts and images without granting the whole disk.
            webView.loadFileURL(target, allowingReadAccessTo: target.deletingLastPathComponent())
        } else {
            webView.load(URLRequest(url: target))
        }
    }
    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reload() { webView.reload() }
    func reloadIgnoringCache() { webView.reloadFromOrigin() }
    func stopLoading() { webView.stopLoading() }

    func focus() { webView.window?.makeFirstResponder(webView) }

    /// Removes the view and stops all work. The page is gone after this.
    func tearDown() {
        observations.removeAll()
        // Detaching a web view doesn't end its page: anything still holding it (an extension's tab
        // reference, a pending callback) would keep the camera and microphone open. Release them now.
        stopCapture()
        webView.pauseAllMediaPlayback { }
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.removeFromSuperview()
    }

    // MARK: Zoom (level 0 = 100%, each step ×1.2)

    var zoomLevel: Double {
        get { log(webView.pageZoom) / log(1.2) }
        set { webView.pageZoom = pow(1.2, newValue) }
    }

    // MARK: Find

    func find(_ text: String, forward: Bool, matchCase: Bool) {
        let config = WKFindConfiguration()
        config.backwards = !forward
        config.caseSensitive = matchCase
        config.wraps = true
        webView.find(text, configuration: config) { [weak self] result in
            guard let self else { return }
            self.delegate?.webTab(self, didFind: result.matchFound)
        }
    }

    func clearFindSelection() {
        webView.evaluateJavaScript("window.getSelection().removeAllRanges()", in: nil, in: .defaultClient) { _ in }
    }

    // MARK: Media, scripting, printing

    /// Ends the page's camera and/or microphone capture (the site must ask again to resume).
    func stopCapture(camera: Bool = true, microphone: Bool = true) {
        if microphone, webView.microphoneCaptureState != .none { webView.setMicrophoneCaptureState(.none) }
        if camera, webView.cameraCaptureState != .none { webView.setCameraCaptureState(.none) }
    }

    /// Mutes or resumes a running capture without ending it.
    func setCaptureMuted(_ muted: Bool, microphone: Bool) {
        let state: WKMediaCaptureState = muted ? .muted : .active
        if microphone { if webView.microphoneCaptureState != .none { webView.setMicrophoneCaptureState(state) } }
        else if webView.cameraCaptureState != .none { webView.setCameraCaptureState(state) }
    }

    /// WebKit has no public mute API: MediaMonitor's script mutes media in every frame that
    /// has reported media, and keeps new playback muted. Re-applied after each load.
    func setMuted(_ muted: Bool) {
        isMuted = muted
        applyMute()
    }

    func applyMute() {
        let script = "window.__ikagoSetMuted && window.__ikagoSetMuted(\(isMuted))"
        webView.evaluateJavaScript(script, in: nil, in: .defaultClient) { _ in }
        for (_, entry) in audibleFrames where !entry.frame.isMainFrame {
            webView.evaluateJavaScript(script, in: entry.frame, in: .defaultClient) { _ in }
        }
    }

    /// Runs `script` in an isolated world the page cannot see or tamper with.
    func evaluate(_ script: String) async throws -> Any? {
        try await webView.evaluateJavaScript(script, in: nil, contentWorld: .defaultClient)
    }

    /// Like `evaluate`, but `body` is a function body that may `await` and must `return`.
    func callAsync(_ body: String) async throws -> Any? {
        try await webView.callAsyncJavaScript(body, arguments: [:], in: nil, contentWorld: .defaultClient)
    }

    func printPage() {
        guard let window = webView.window else { return }
        let operation = webView.printOperation(with: NSPrintInfo.shared)
        operation.view?.frame = webView.bounds
        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    // MARK: Developer tools (Web Inspector inside Ikago)

    /// Adds Inspect Element to the page's context menu.
    // SPI: WKPreferences "developerExtrasEnabled" — no public way to enable the in-app inspector.
    func setDeveloperTools(_ enabled: Bool) {
        webView.isInspectable = enabled  // Safari's Develop menu can attach only while this is on
        let preferences = webView.configuration.preferences
        guard preferences.responds(to: NSSelectorFromString("_setDeveloperExtrasEnabled:"))
            || preferences.responds(to: NSSelectorFromString("setDeveloperExtrasEnabled:")) else { return }
        preferences.setValue(enabled, forKey: "developerExtrasEnabled")
    }

    /// Opens or closes the Web Inspector docked in this page (⌥⌘I).
    // SPI: WKWebView._inspector (_WKInspector show/close/isVisible) — public API can't open it.
    func toggleInspector() {
        guard let inspector = inspectorObject else { return }
        let selector = NSSelectorFromString(isInspectorVisible ? "close" : "show")
        if inspector.responds(to: selector) { inspector.perform(selector) }
    }

    var isInspectorVisible: Bool {
        guard let inspector = inspectorObject, inspector.responds(to: NSSelectorFromString("isVisible")) else { return false }
        return (inspector.value(forKey: "isVisible") as? Bool) ?? false
    }

    private var inspectorObject: NSObject? {
        let selector = NSSelectorFromString("_inspector")
        guard webView.responds(to: selector) else { return nil }
        return webView.perform(selector)?.takeUnretainedValue() as? NSObject
    }

    func snapshot() async throws -> NSImage {
        try await webView.takeSnapshot(configuration: nil)
    }
}
