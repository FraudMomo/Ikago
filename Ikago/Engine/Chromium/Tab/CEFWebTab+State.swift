import AppKit
import WebKit

extension CEFWebTab {
    func reportMedia() {
        delegate?.webTab(self, didChangeMedia: isAudible, camera: cameraActive ? .active : .none,
                         microphone: microphoneActive ? .active : .none)
    }
    var isPageShown: Bool { page.window != nil && !page.isHiddenOrHasHiddenAncestor }

    func refreshFavicon() { pickFavicon(fallback: nil) }

    /// Chromium reports its first icon candidate, ignoring `media`; choose the one for Ikago's mode in the top
    /// document's isolated world (`FaviconScript`), and fall back to Chromium's when the script finds none.
    func pickFavicon(fallback: URL?) {
        guard !isTornDown, page.ready else { return }
        let generation = documentGeneration, dark = FaviconCache.shared.dark
        Task { @MainActor [weak self] in
            guard let self else { return }
            var picked: URL?
            if let tree = try? await devTools("Page.getFrameTree", [:], generation: generation),
               let id = ((tree["frameTree"] as? [String: Any])?["frame"] as? [String: Any])?["id"] as? String,
               let world = try? await devTools("Page.createIsolatedWorld", ["frameId": id, "worldName": "ikago-browser"], generation: generation),
               let context = world["executionContextId"] as? Int,
               let result = try? await devTools("Runtime.evaluate", ["expression": FaviconScript.pick(dark: dark),
                                                                    "contextId": context, "returnByValue": true], generation: generation) {
                picked = ((result["result"] as? [String: Any])?["value"] as? String).flatMap(URL.init(string:))
            }
            guard !self.isTornDown, generation == self.documentGeneration, let url = picked ?? fallback else { return }
            self.delegate?.webTab(self, didFindFavicon: url)
        }
    }

    /// A frame loaded or detached: subscribe once to each new isolated context, without a polling loop.
    func observePageState() {
        stateTask?.cancel()
        guard !isTornDown, page.ready else { return }
        stateTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let generation = documentGeneration
            _ = try? await devTools("Page.enable", [:], generation: generation)
            guard let tree = try? await devTools("Page.getFrameTree", [:], generation: generation),
                  let root = tree["frameTree"] as? [String: Any], !Task.isCancelled else { return }
            func frames(_ node: [String: Any]) -> [String] {
                let id = (node["frame"] as? [String: Any])?["id"] as? String
                return (id.map { [$0] } ?? []) + ((node["childFrames"] as? [[String: Any]]) ?? []).flatMap(frames)
            }
            var live: Set<Int> = []
            for (index, id) in frames(root).enumerated() {
                guard !Task.isCancelled,
                      let world = try? await devTools("Page.createIsolatedWorld", ["frameId": id, "worldName": "ikago-browser"], generation: generation),
                      let context = world["executionContextId"] as? Int else { continue }
                live.insert(context)
                if index == 0 { pageStateRoot = context }
                guard !pageStateContexts.contains(context) else { continue }
                do {
                    // Bind to an existing isolated context explicitly; Runtime.enable is never needed.
                    _ = try await devTools("Runtime.addBinding", ["name": "__ikagoStateChanged", "executionContextId": context], generation: generation)
                    guard !Task.isCancelled else { return }
                    pageStateContexts.insert(context)
                    _ = try await devTools("Runtime.evaluate", ["expression": CEFPageStateScript.source,
                        "contextId": context, "returnByValue": true], generation: generation)
                    stateScriptInstalls += 1
                    // The notification shim goes into the page's own world once the listener that hears it exists. (Not a
                    // document-start script: registering one makes Back through a restored tab's history stall.)
                    if index == 0, wantsNotificationShim {
                        _ = try? await devTools("Runtime.evaluate", ["expression": NotificationShim.chromium, "userGesture": false], generation: generation)
                    }
                } catch { pageStateContexts.remove(context) }
            }
            guard !Task.isCancelled, documentGeneration == generation else { return }
            pageStateContexts.formIntersection(live)
            pageFrameReports = pageFrameReports.filter { live.contains($0.key) }
            updatePlayback(Array(pageFrameReports.values))
        }
    }

    func receivePageState(_ payload: [AnyHashable: Any]) {
        guard let context = payload["executionContextId"] as? Int, pageStateContexts.contains(context),
              let json = payload["payload"] as? String, let data = json.data(using: .utf8), data.count <= 65536,
              let state = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        if let peek = ShiftClickPeek.url(state["peek"]) {
            if delegate?.webTab(self, peeks: peek, trigger: .shiftClick) != true {
                delegate?.webTab(self, openInNewTab: peek.absoluteString, background: false)
            }
            return
        }
        if let notification = state["notify"] as? String {
            if context == pageStateRoot { delegate?.webTab(self, notification: notification) }
            return
        }
        guard let media = state["media"] as? [String: Any] else { return }
        pageFrameReports[context] = media
        // A page started Chromium's own Picture in Picture, whose window Ikago never shows: float it in Ikago's panel.
        if let pip = state["pip"] as? Int, pip > (pagePictureInPictureCounts[context] ?? 0) {
            pagePictureInPictureCounts[context] = pip
            if !floatingVideo.isActive { Task { @MainActor [weak self] in try? await self?.pictureInPicture() } }
        }
        updatePlayback(Array(pageFrameReports.values))
        if media["unsupportedVideo"] as? Bool == true { nativeVideoRequested = true; nativeVideo.inject() }
        guard context == pageStateRoot else { return }
        let color = (state["color"] as? [Double]).flatMap { values -> NSColor? in
            guard values.count == 4 else { return nil }
            return NSColor(srgbRed: values[0]/255, green: values[1]/255, blue: values[2]/255, alpha: values[3]/255)
        }
        if color != lastPolledThemeColor {
            lastPolledThemeColor = color
            delegate?.webTab(self, didChangeThemeColor: color)
        }
    }
}

extension CEFWebTab {
    /// Hands a message to the shim in the page's own world (no context: the top frame's main world).
    func sendNotificationMessage(_ message: [String: Any]) {
        guard let script = NotificationShim.replyScript(message), !isTornDown else { return }
        let generation = documentGeneration
        Task { @MainActor in
            _ = try? await devTools("Runtime.evaluate", ["expression": script, "userGesture": false], generation: generation)
        }
    }
}

extension CEFWebTab {
    /// Pages may ask for notifications, except in private windows and when Settings turned them off.
    var wantsNotificationShim: Bool {
        !profileID.hasPrefix("Private-") && BrowserSecurity.shared.preferences.websiteNotifications != false
    }
}
