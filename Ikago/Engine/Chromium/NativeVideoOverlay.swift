import AppKit
import AVFoundation
import AVKit

/// Plays videos Chromium can't (H.264/AAC, which the prebuilt CEF leaves out) with macOS's own player,
/// placed exactly over the page's video and clipped to what's visible. Like X: videos at least half on
/// screen play muted, leave and they pause; unmuting or pausing one is remembered. Scrolling passes
/// through to the page. One per Chromium tab; it polls the isolated "ikago-media" world, so the page
/// never talks to Ikago.
@MainActor
final class NativeVideoOverlay {
    private weak var tab: CEFWebTab?
    private var context: Int?
    private var injectedGeneration = -1
    private var injecting = false
    private var timer: Timer?
    private var polling = false
    private var players: [Int: NativeVideoPlayer] = [:]
    private var resolving: Set<Int> = []
    private var failed: Set<Int> = []
    /// The person unmuted a video: later ones in this tab start with sound, like X.
    var prefersSound = false
    var tabMuted = false
    var isAudible: Bool { players.values.contains { $0.isAudible } }
    var playback: MediaPlaybackState {
        let states = players.values.map(\.playback)
        return states.first { $0.available && $0.playing } ?? states.first { $0.available } ?? MediaPlaybackState()
    }

    func setTabMuted(_ muted: Bool) {
        tabMuted = muted
        players.values.forEach { $0.setTabMuted(muted) }
    }

    func control(_ action: MediaPlaybackAction) {
        for player in players.values where player.playback.available {
            player.control(action)
            if action != .pause { break }
        }
    }
    private var lastActivity = Date.distantPast

    init(tab: CEFWebTab) { self.tab = tab }

    /// A new document: forget the old one's videos and inject into the new one.
    func documentChanged() {
        removeAll()
        context = nil
        injectedGeneration = -1
        inject()
    }

    func tearDown() {
        timer?.invalidate()
        timer = nil
        removeAll()
    }

    /// The tab was shown or parked: resume polling an injected document once it can be seen.
    func visibilityChanged() {
        guard timer == nil, let tab, !tab.isTornDown, context != nil, injectedGeneration == tab.documentGeneration,
              tab.isPageShown else { return }
        schedule(fast: false)
    }

    private func removeAll() {
        players.values.forEach { $0.remove() }
        players.removeAll()
        resolving.removeAll()
        failed.removeAll()
    }

    func inject() {
        guard let tab, !tab.isTornDown, !injecting, injectedGeneration != tab.documentGeneration,
              URL(string: tab.currentURL)?.scheme == "https" else { return }
        injecting = true
        Task { @MainActor in
            defer { injecting = false }
            for _ in 0..<10 {
                guard let tab = self.tab, !tab.isTornDown else { return }
                let generation = tab.documentGeneration
                do {
                    let tree = try await tab.devTools("Page.getFrameTree", [:], generation: generation)
                    guard let frame = (tree["frameTree"] as? [String: Any])?["frame"] as? [String: Any],
                          let frameID = frame["id"] as? String else { throw CEFError.noResult }
                    let world = try await tab.devTools("Page.createIsolatedWorld", ["frameId": frameID, "worldName": NativeVideoScript.world], generation: generation)
                    guard let id = world["executionContextId"] as? Int else { throw CEFError.noResult }
                    _ = try await tab.devTools("Runtime.evaluate", ["expression": NativeVideoScript.source, "contextId": id, "userGesture": false], generation: generation)
                    context = id
                    injectedGeneration = generation
                    schedule(fast: false)
                    return
                } catch {
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
        }
    }

    /// 30 polls a second while a native video is on screen or the page just moved; twice a second otherwise.
    private func schedule(fast: Bool) {
        let interval = fast ? 1.0 / 30 : 0.5
        if let timer, abs(timer.timeInterval - interval) < 0.001 { return }
        timer?.invalidate()
        let next = Timer(timeInterval: interval, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.poll() } }
        next.tolerance = interval / 4
        RunLoop.main.add(next, forMode: .common)
        timer = next
    }

    private func poll() {
        guard let tab, !tab.isTornDown, !polling, let context, injectedGeneration == tab.documentGeneration else { return }
        // A parked tab: pause and hide, and stop polling until it's shown (`visibilityChanged`).
        guard let window = tab.page.window, !tab.page.isHiddenOrHasHiddenAncestor else {
            players.values.forEach { $0.hide() }
            timer?.invalidate()
            timer = nil
            return
        }
        // A hidden window (minimized, another Space): check rarely.
        guard window.isVisible else {
            players.values.forEach { $0.hide() }
            schedule(fast: false)
            return
        }
        polling = true
        let generation = tab.documentGeneration
        Task { @MainActor in
            defer { polling = false }
            let result = try? await tab.devTools("Runtime.callFunctionOn", [
                "functionDeclaration": "function (translating) { return window.__ikagoMedia ? window.__ikagoMedia.scan(translating) : [] }",
                "executionContextId": context, "arguments": [["value": MediaTranslation.isEnabled]], "returnByValue": true], generation: generation)
            guard generation == tab.documentGeneration,
                  let list = (result?["result"] as? [String: Any])?["value"] as? [[String: Any]] else { return }
            update(list.compactMap(NativeVideoReport.init), in: tab)
        }
    }

    private func update(_ reports: [NativeVideoReport], in tab: CEFWebTab) {
        let seen = Set(reports.map(\.key))
        for (key, player) in players where !seen.contains(key) { player.hide() }
        let zoom = pow(1.2, tab.zoomLevel)
        let viewport = NSRect(x: 0, y: 0, width: tab.page.bounds.width, height: max(0, tab.page.bounds.height - tab.page.topInset))
        for report in reports {
            if let player = players[report.key] {
                player.place(report, zoom: zoom, viewport: viewport, in: tab.page)
                if player.moved { lastActivity = Date() }
            } else if report.request.kind == "x", MediaTranslation.isEnabled, !report.fallback {
                continue  // X's own player plays it through the translation layer
            } else if !resolving.contains(report.key), !failed.contains(report.key) {
                resolve(report, in: tab)
            }
        }
        // Few players live at once: drop the ones furthest out of sight.
        if players.count > 8 {
            for key in players.keys.filter({ !seen.contains($0) }).prefix(players.count - 8) { players.removeValue(forKey: key)?.remove() }
        }
        let active = players.values.contains { $0.isShown } || Date().timeIntervalSince(lastActivity) < 1
        tab.updatePlayback(tab.lastMediaReports)
        schedule(fast: active || !resolving.isEmpty)
    }

    private func resolve(_ report: NativeVideoReport, in tab: CEFWebTab) {
        resolving.insert(report.key)
        let generation = tab.documentGeneration
        Task { @MainActor in
            let stream = await NativeVideoSource.stream(for: report.request)
            resolving.remove(report.key)
            guard let tab = self.tab, generation == tab.documentGeneration, !tab.isTornDown else { return }
            guard let stream else { failed.insert(report.key); return }
            players[report.key] = NativeVideoPlayer(stream: stream, owner: self, page: tab.page)
        }
    }
}

/// One video as the isolated script reports it, in CSS pixels of the viewport.
struct NativeVideoReport {
    let key: Int
    let frame: CGRect
    let shown: Double
    let covered: Bool
    let hiddenTop: Double
    let fallback: Bool
    let request: NativeVideoSource.Request

    init?(_ value: [String: Any]) {
        guard let key = value["key"] as? Int, let kind = value["kind"] as? String,
              let x = value["x"] as? Double, let y = value["y"] as? Double,
              let width = value["width"] as? Double, let height = value["height"] as? Double,
              [x, y, width, height].allSatisfy(\.isFinite), width > 0, height > 0 else { return nil }
        self.key = key
        frame = CGRect(x: x, y: y, width: width, height: height)
        shown = value["shown"] as? Double ?? 0
        covered = value["covered"] as? Bool ?? false
        hiddenTop = max(0, min(height, value["hiddenTop"] as? Double ?? 0))
        fallback = value["fallback"] as? Bool ?? false
        request = .init(kind: kind, src: value["src"] as? String, status: value["status"] as? String,
                        token: value["token"] as? String, thumb: value["thumb"] as? String, media: value["media"] as? String)
    }
}
