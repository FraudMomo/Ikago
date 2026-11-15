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
        if floatingVideo.isActive { floatingVideo.end(); return }
        if nativeVideo.pictureInPicture(page: self) { return }
        if try await floatVideo() { return }
        // A video Chromium can't play itself (H.264 files): AVKit's player, for direct addresses.
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

    func endPictureInPicture() { floatingVideo.end() }

    /// The playing video in Ikago's floating panel (`ChromiumPictureInPicture`): it goes fullscreen inside its frame, with
    /// a user gesture, and the panel takes the page view when Chromium reports the fullscreen. False when no frame has a
    /// video Chromium is playing.
    private func floatVideo() async throws -> Bool {
        let generation = documentGeneration
        let tree = try await devTools("Page.getFrameTree", [:], generation: generation)
        guard let root = tree["frameTree"] as? [String: Any] else { return false }
        func frames(_ node: [String: Any]) -> [String] {
            let own = (node["frame"] as? [String: Any])?["id"] as? String
            return (own.map { [$0] } ?? []) + ((node["childFrames"] as? [[String: Any]]) ?? []).flatMap(frames)
        }
        for id in frames(root) {
            guard let world = try? await devTools("Page.createIsolatedWorld", ["frameId": id, "worldName": "ikago-browser"], generation: generation),
                  let context = world["executionContextId"] as? Int else { continue }
            floatingVideo.expectFullscreen()
            guard let result = try? await devTools("Runtime.evaluate", [
                "expression": "(async () => {\n\(ChromiumPictureInPicture.prepare)\n})()", "contextId": context,
                "returnByValue": true, "awaitPromise": true, "userGesture": true
            ], generation: generation), let value = (result["result"] as? [String: Any])?["value"] as? [String: Any],
                  value["video"] as? Bool == true else { floatingVideo.cancelExpectation(); continue }
            if let failure = value["failed"] as? String {
                floatingVideo.cancelExpectation()
                throw CEFError.script("This video can’t play in Picture in Picture (\(failure)).")
            }
            floatingVideo.setAspect(width: value["width"] as? Double ?? 16, height: value["height"] as? Double ?? 9)
            return true
        }
        return false
    }

    func controlMedia(_ action: MediaPlaybackAction) async {
        let generation = documentGeneration
        nativeVideo.control(action)
        let reports = await mediaFrames(action: action)
        guard generation == documentGeneration, !isTornDown else { return }
        updatePlayback(reports)
    }
}

// MARK: - Session history

extension CEFWebTab {
    /// The addresses behind the page (Chromium can't restore its own history entries).
    func sessionHistory() async -> TabHistory? {
        guard let result = try? await devTools("Page.getNavigationHistory", [:], generation: documentGeneration),
              let entries = result["entries"] as? [[String: Any]], let index = result["currentIndex"] as? Int, index > 0 else { return nil }
        return TabHistory.trimmed(entries.prefix(index).compactMap { $0["url"] as? String }).map { TabHistory(back: $0) }
    }
}
