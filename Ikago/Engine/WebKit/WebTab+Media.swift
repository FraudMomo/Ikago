import WebKit

extension WebKitTab {
    func controlMedia(_ action: MediaPlaybackAction) async {
        // Embedded players can live in cross-origin frames. Use the exact frames which
        // reported playback, rather than evaluating only in the main document.
        let entries = audibleFrames.values.filter { $0.playback.available }
        for entry in entries where action == .pause || entry.playback.playing || !entries.contains(where: { $0.playback.playing }) {
            do {
                if let report = try await webView.callAsyncJavaScript(MediaPlaybackScript.control(action), arguments: [:],
                    in: entry.frame.isMainFrame ? nil : entry.frame, contentWorld: .defaultClient) as? [String: Any] {
                    frameReportedAudio(report["audible"] as? Bool ?? false,
                                       playback: MediaPlaybackState(report), frame: entry.frame)
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
