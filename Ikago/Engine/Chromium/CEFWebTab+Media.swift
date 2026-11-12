import Foundation

extension CEFWebTab {
    func hasNavigationHistory() async -> Bool {
        guard let result = try? await devTools("Page.getNavigationHistory", [:], generation: documentGeneration),
              let entries = result["entries"] as? [[String: Any]] else { return true }
        return entries.count > 1
    }

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
        var next = states.first { $0.available && $0.playing } ?? states.first { $0.available } ?? MediaPlaybackState()
        next.hasVideo = states.contains { $0.available && $0.hasVideo }
        if playback != next { playback = next; delegate?.webTab(self, didChangePlayback: playback) }
        let audible = (reports.contains { $0["audible"] as? Bool == true } || nativeVideo.isAudible) && !isMuted
        if isAudible != audible { isAudible = audible; reportMedia() }
    }

    func pictureInPicture() async throws {
        if nativeVideo.pictureInPicture(page: self) { return }
        // CEF stays embedded; never create a Chromium-owned PiP window.
        let reports = try await devTools("Page.getFrameTree", [:])
        guard let tree = reports["frameTree"] as? [String: Any] else { throw MediaPictureInPicture.Issue.noVideo }
        func frames(_ tree: [String: Any]) -> [String] {
            let current = (tree["frame"] as? [String: Any])?["id"] as? String
            return (current.map { [$0] } ?? []) + ((tree["childFrames"] as? [[String: Any]]) ?? []).flatMap(frames)
        }
        let generation = documentGeneration
        for id in frames(tree) {
            guard let world = try? await devTools("Page.createIsolatedWorld", ["frameId": id, "worldName": "ikago-browser"], generation: generation),
                  let context = world["executionContextId"] as? Int,
                  let result = try? await devTools("Runtime.evaluate", ["expression": "(async()=>{\(MediaPictureInPicture.source)})()", "contextId": context,
                    "returnByValue": true, "awaitPromise": true, "userGesture": false], generation: generation),
                  let value = (result["result"] as? [String: Any])?["value"] as? [String: Any],
                  value["video"] as? Bool == true else { continue }
            try MediaPictureInPicture.finish(value, page: self)
            return
        }
        throw MediaPictureInPicture.Issue.noVideo
    }

    func controlMedia(_ action: MediaPlaybackAction) async {
        let generation = documentGeneration
        nativeVideo.control(action)
        let reports = await mediaFrames(action: action)
        guard generation == documentGeneration, !isTornDown else { return }
        updatePlayback(reports)
    }
}
