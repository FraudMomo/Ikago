import AppKit
import WebKit

/// The shell owns pages through this interface; engine choice never changes layout.
@MainActor
protocol WebTab: AnyObject {
    var engine: BrowserEngine { get }
    var contentView: NSView { get }
    var delegate: WebTabDelegate? { get set }
    var currentURL: String { get }
    var isLoading: Bool { get }
    var isAudible: Bool { get }
    var isMuted: Bool { get }
    var zoomLevel: Double { get set }
    var isInspectorVisible: Bool { get }
    var performanceProcessID: Int32? { get }
    func load(_ url: String)
    func goBack()
    func goForward()
    func reload()
    func reloadIgnoringCache()
    func stopLoading()
    func focus()
    func tearDown()
    func find(_ text: String, forward: Bool, matchCase: Bool)
    func clearFindSelection()
    func stopCapture(camera: Bool, microphone: Bool)
    func setCaptureMuted(_ muted: Bool, microphone: Bool)
    func setMuted(_ muted: Bool)
    func pictureInPicture() async throws
    /// The page's Back history for the session (`TabHistory`), nil when there is nothing to keep.
    func sessionHistory() async -> TabHistory?
    /// Restores saved history into a page that hasn't loaded yet, in place of loading its address. False when the
    /// engine can't (Chromium); the tab then goes back through `TabHistory.back` itself.
    func restoreHistory(_ history: TabHistory) -> Bool
    /// Ends Picture in Picture the page drew itself (Chromium's panel) before the page moves to another window.
    func endPictureInPicture()
    func controlMedia(_ action: MediaPlaybackAction) async
    func evaluate(_ script: String) async throws -> Any?
    func callAsync(_ body: String) async throws -> Any?
    func printPage()
    /// Tells the page's Notification shim (permission, or a notification's show, click and close).
    func sendNotificationMessage(_ message: [String: Any])
    /// Writes the page to `url` as a web archive or PDF (File ▸ Save Page As…).
    func savePage(as format: PageSaveFormat, to url: URL) async throws
    /// Looks up the page's icon again for Ikago's current light or dark mode (`FaviconScript`).
    func refreshFavicon()
    func setDeveloperTools(_ enabled: Bool)
    func toggleInspector()
    func snapshot() async throws -> NSImage
    /// The page was just shown or parked; background polling runs only while it can be seen.
    func visibilityChanged()
    func pauseForHistory()
    func hasNavigationHistory() async -> Bool
}
extension WebTab {
    var performanceProcessID: Int32? { nil }
    func controlMedia(_ action: MediaPlaybackAction) async {
        if let report = try? await callAsync(MediaPlaybackScript.control(action)) as? [String: Any] {
            delegate?.webTab(self, didChangePlayback: MediaPlaybackState(report))
        }
    }
    func stopCapture() { stopCapture(camera: true, microphone: true) }
    func visibilityChanged() {}
    func endPictureInPicture() {}
    func sessionHistory() async -> TabHistory? { nil }
    func restoreHistory(_ history: TabHistory) -> Bool { false }
    /// Goes to `url` in place of the current history entry (Back through restored history, without stacking entries).
    func replace(with url: String) {
        guard let data = try? JSONEncoder().encode(url), let literal = String(data: data, encoding: .utf8) else { return load(url) }
        Task { @MainActor in
            // Answer first, then go: navigating right away ends the script before it can answer, which read as a
            // failure and loaded the page a second time, stacking an entry.
            if (try? await callAsync("setTimeout(() => location.replace(\(literal)), 0); return true")) != nil { return }
            // No answer can still mean the replace ran (the frame went away mid-reply). Load only if it didn't start.
            try? await Task.sleep(for: .milliseconds(250))
            if !isLoading, currentURL != url { load(url) }
        }
    }
    func pauseForHistory() { Task { @MainActor in await controlMedia(.pause) } }
    func hasNavigationHistory() async -> Bool { true }
}

enum CEFError: LocalizedError {
    case closed, noResult, script(String)
    var errorDescription: String? {
        switch self {
        case .closed: "This page has closed or navigated."
        case .noResult: "The page returned no usable result."
        case .script(let message): message
        }
    }
}
