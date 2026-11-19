import Foundation

/// macOS memory-pressure events trigger reclamation (normal pressure cancels it), and with Conservative or Balanced a
/// background tab left unused past the policy's time sleeps, as Chrome's Memory Saver and Edge's sleeping tabs do.
@MainActor
final class TabMemoryManagement {
    private weak var content: WebContentViewController?
    private var source: DispatchSourceMemoryPressure?
    private var task: Task<Void, Never>?
    private var pressure = BrowserMemoryPressure.normal
    private var lastUsed: [String: Date] = [:]
    private var idleTask: Task<Void, Never>?

    init(content: WebContentViewController) {
        self.content = content
        // Fixtures inject pressure directly, never react to the real Mac's memory state.
        guard !WebProfiles.isTestMode, EngineCookieSync.usesRealStores else { return }
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)
        source.setEventHandler { [weak self, weak source] in
            MainActor.assumeIsolated {
                guard let self, let source else { return }
                let level: BrowserMemoryPressure = source.data.contains(.critical) ? .critical
                    : source.data.contains(.warning) ? .warning : .normal
                self.task?.cancel()
                self.pressure = level
                if level != .normal { self.task = Task { [weak self] in await self?.reclaim(level) } }
            }
        }
        self.source = source
        source.resume()
        // A cheap check every five minutes; it only acts on tabs past the chosen policy's time.
        idleTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300), tolerance: .seconds(60))
                self?.sleepIdleTabs()
            }
        }
    }

    deinit { source?.cancel(); task?.cancel(); idleTask?.cancel() }

    func stop() { source?.cancel(); source = nil; task?.cancel(); task = nil; idleTask?.cancel(); idleTask = nil }

    /// Background tabs unused for longer than the policy allows go to sleep, the least recently used first. A tab Ikago
    /// hasn't seen in use since launch counts from now, so nothing sleeps the moment a session is restored.
    func sleepIdleTabs(now: Date = Date()) {
        guard let content, !content.state.isFrozen, task == nil || pressure == .normal,
              let limit = content.state.browserPreferences.resourcePolicy.idleSleep else { return }
        let seconds = TimeInterval(limit.components.seconds)
        for controller in content.controllers.values where controller.page != nil {
            let id = controller.tab.id
            guard let used = lastUsed[id] else { lastUsed[id] = now; continue }
            guard now.timeIntervalSince(used) >= seconds, eligible(controller, level: .warning, idle: true) else { continue }
            controller.hibernate()
        }
    }

    /// Tabs on screen now. A tab's idle time counts from when it was last on screen, so leaving one stamps it too.
    private var onScreen = Set<String>()

    func markVisible() {
        guard let content else { return }
        let live = Set(content.state.tabs.map(\.id))
        lastUsed = lastUsed.filter { live.contains($0.key) }
        let now = Date(), visible = Set(content.state.visibleTabIDs)
        for id in visible.union(onScreen) { lastUsed[id] = now }
        onScreen = visible
    }

    private func eligible(_ controller: TabController, level: BrowserMemoryPressure, idle: Bool = false) -> Bool {
        guard let content, !content.state.isFrozen, controller.page != nil, !controller.isPopup,
              !controller.isActive, !content.state.visibleTabIDs.contains(controller.tab.id),
              AddressResolver.isWebURL(controller.tab.url) else { return false }
        let preferences = content.state.browserPreferences
        guard idle || level == .critical || (level == .warning && preferences.resourcePolicy.reclaimsOnWarning) else { return false }
        let tab = controller.tab
        return !tab.isLoading && !tab.isPlayingAudio && !tab.playback.playing && !tab.cameraActive && !tab.microphoneActive
            && !(preferences.protectPinnedTabs && tab.pinned) && !preferences.protects(tab.url)
            && controller.page?.isInspectorVisible != true && !AgentActivity.shared.drives(tab.id)
    }

    /// Releases inactive pages oldest-first while pressure remains. No fixed tab count or RAM budget.
    func reclaim(_ level: BrowserMemoryPressure) async {
        guard !Task.isCancelled else { return }
        pressure = level
        guard level != .normal, let content, !content.state.isFrozen else { return }
        FaviconCache.shared.trimMemory()
        let preferences = content.state.browserPreferences
        guard level == .critical || preferences.resourcePolicy.reclaimsOnWarning else { return }
        for controller in Array(content.controllers.values) {
            guard !Task.isCancelled, pressure == level else { return }
            guard level == .critical || content.state.browserPreferences.resourcePolicy.reclaimsOnWarning else { return }
            await controller.releaseParkedMemory()
        }
        let candidates = content.controllers.values.sorted {
            (lastUsed[$0.tab.id] ?? .distantPast) < (lastUsed[$1.tab.id] ?? .distantPast)
        }
        for controller in candidates {
            guard !Task.isCancelled, pressure == level else { return }
            guard eligible(controller, level: level), let page = controller.page,
                  await controller.canReleaseMemory(), !Task.isCancelled, pressure == level,
                  controller.page === page, eligible(controller, level: level) else { continue }
            controller.hibernate()
            await Task.yield() // Let normal-pressure events stop reclamation as soon as the Mac has recovered.
        }
    }
}
