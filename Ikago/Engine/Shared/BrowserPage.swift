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
    func load(_ url: String)
    func goBack()
    func goForward()
    func reload()
    func reloadIgnoringCache()
    func stopLoading()
    func focus()
    func tearDown()
    func setTopInset(_ inset: CGFloat)
    func snapshotBelowInset(_ inset: CGFloat, completion: @escaping (NSImage?) -> Void)
    func find(_ text: String, forward: Bool, matchCase: Bool)
    func clearFindSelection()
    func stopCapture(camera: Bool, microphone: Bool)
    func setCaptureMuted(_ muted: Bool, microphone: Bool)
    func setMuted(_ muted: Bool)
    func controlMedia(_ action: MediaPlaybackAction) async
    /// Band levels (0…1) of the sound the page plays now, when Ikago can hear it: Chromium pages, whose sound Ikago
    /// plays itself (`IKCEFAudio`). WebKit's sound never passes through Ikago, so it has none.
    var audioLevels: [CGFloat]? { get }
    func evaluate(_ script: String) async throws -> Any?
    func callAsync(_ body: String) async throws -> Any?
    func printPage()
    func setDeveloperTools(_ enabled: Bool)
    func toggleInspector()
    func snapshot() async throws -> NSImage
    /// The page was just shown or parked; background polling runs only while it can be seen.
    func visibilityChanged()
}
extension WebTab {
    var audioLevels: [CGFloat]? { nil }
    func controlMedia(_ action: MediaPlaybackAction) async {
        if let report = try? await callAsync(MediaPlaybackScript.control(action)) as? [String: Any] {
            delegate?.webTab(self, didChangePlayback: MediaPlaybackState(report))
        }
    }
    func stopCapture() { stopCapture(camera: true, microphone: true) }
    func visibilityChanged() {}
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
