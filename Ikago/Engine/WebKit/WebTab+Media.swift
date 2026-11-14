import WebKit

extension WebKitTab {
    func pauseForHistory() { webView.pauseAllMediaPlayback {} }
    func hasNavigationHistory() async -> Bool {
        !webView.backForwardList.backList.isEmpty || !webView.backForwardList.forwardList.isEmpty
    }
    func controlMedia(_ action: MediaPlaybackAction) async {
        // Embedded players can live in cross-origin frames. Use the exact frames which
        // reported playback, rather than evaluating only in the main document.
        let entries = audibleFrames.filter { $0.value.playback.available }
        for (document, entry) in entries where action == .pause || entry.playback.playing || !entries.values.contains(where: { $0.playback.playing }) {
            do {
                if let report = try await webView.callAsyncJavaScript(MediaPlaybackScript.control(action), arguments: [:],
                    in: entry.frame.isMainFrame ? nil : entry.frame, contentWorld: .defaultClient) as? [String: Any] {
                    frameReportedAudio(report["audible"] as? Bool ?? false,
                                       playback: MediaPlaybackState(report), frame: entry.frame, document: document)
                }
            } catch {
                #if DEBUG
                print("IKTEST media control failed code=\((error as NSError).code) main=\(entry.frame.isMainFrame)")
                #endif
            }
            if action != .pause { break }
        }
    }
}
