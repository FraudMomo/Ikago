import Foundation
import IKCEFBridge

extension CEFWebTab {
    /// Read and control embedded players too, without crossing their origin in script.
    /// Each frame gets its own isolated world through Chromium's public DevTools API.
    func mediaFrames(action: MediaPlaybackAction? = nil) async -> [[String: Any]] {
        let generation = documentGeneration
        guard let tree = try? await devTools("Page.getFrameTree", [:], generation: generation),
              let root = tree["frameTree"] as? [String: Any] else { return [] }
        func frameIDs(_ node: [String: Any]) -> [String] {
            let own = (node["frame"] as? [String: Any])?["id"] as? String
            return (own.map { [$0] } ?? []) + ((node["childFrames"] as? [[String: Any]]) ?? []).flatMap(frameIDs)
        }
        var reports: [[String: Any]] = []
        for id in frameIDs(root) {
            guard let world = try? await devTools("Page.createIsolatedWorld", ["frameId": id, "worldName": "ikago-browser"], generation: generation),
                  let context = world["executionContextId"] as? Int else { continue }
            let body = action.map(MediaPlaybackScript.control)
                ?? "\(MediaPlaybackScript.install)\nreturn window.__ikagoMedia.state();"
            guard let result = try? await devTools("Runtime.evaluate", [
                "expression": "(async () => {\n\(body)\n})()", "contextId": context,
                "returnByValue": true, "awaitPromise": true, "userGesture": false
            ], generation: generation), let value = result["result"] as? [String: Any],
                  let report = value["value"] as? [String: Any] else { continue }
            reports.append(report)
            if action != nil, action != .pause, report["available"] as? Bool == true { break }
        }
        return reports
    }

    func updatePlayback(_ reports: [[String: Any]]) {
        lastMediaReports = reports
        let states = reports.map(MediaPlaybackState.init) + [nativeVideo.playback]
        playback = states.first { $0.available && $0.playing } ?? states.first { $0.available } ?? MediaPlaybackState()
        delegate?.webTab(self, didChangePlayback: playback)
        let audible = (reports.contains { $0["audible"] as? Bool == true } || nativeVideo.isAudible) && !isMuted
        if isAudible != audible { isAudible = audible; reportMedia() }
    }

    func controlMedia(_ action: MediaPlaybackAction) async {
        let generation = documentGeneration
        nativeVideo.control(action)
        let reports = await mediaFrames(action: action)
        guard generation == documentGeneration, !isTornDown else { return }
        updatePlayback(reports)
    }

    var audioLevels: [CGFloat]? {
        IKCEFAudio.levels(forBrowser: page.browserIdentifier)?.map { CGFloat($0.doubleValue) }
    }
}
