import Foundation

/// No expiry clock: macOS memory-pressure events trigger reclamation, and normal pressure cancels it.
@MainActor
final class TabMemoryManagement {
    private weak var content: WebContentViewController?
    private var source: DispatchSourceMemoryPressure?
    private var task: Task<Void, Never>?
    private var pressure = BrowserMemoryPressure.normal
    private var lastUsed: [String: Date] = [:]

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
    }

    deinit { source?.cancel(); task?.cancel() }

    func stop() { source?.cancel(); source = nil; task?.cancel(); task = nil }

    func markVisible() {
        guard let content else { return }
        let live = Set(content.state.tabs.map(\.id))
        lastUsed = lastUsed.filter { live.contains($0.key) }
        for id in content.state.visibleTabIDs { lastUsed[id] = Date() }
    }

    private func eligible(_ controller: TabController, level: BrowserMemoryPressure) -> Bool {
        guard let content, !content.state.isFrozen, controller.page != nil, !controller.isPopup,
              !controller.isActive, AddressResolver.isWebURL(controller.tab.url) else { return false }
        let preferences = content.state.browserPreferences
        guard level == .critical || (level == .warning && preferences.resourcePolicy == .conservative) else { return false }
        let tab = controller.tab
        return !tab.isLoading && !tab.isPlayingAudio && !tab.playback.playing && !tab.cameraActive && !tab.microphoneActive
            && !(preferences.protectPinnedTabs && tab.pinned) && !preferences.protects(tab.url)
            && controller.page?.isInspectorVisible != true
    }

    /// Releases inactive pages oldest-first while pressure remains. No fixed tab count or RAM budget.
    func reclaim(_ level: BrowserMemoryPressure) async {
        guard !Task.isCancelled else { return }
        pressure = level
        guard level != .normal, let content, !content.state.isFrozen else { return }
        FaviconCache.shared.trimMemory()
        let preferences = content.state.browserPreferences
        guard level == .critical || preferences.resourcePolicy == .conservative else { return }
        for controller in Array(content.controllers.values) {
            guard !Task.isCancelled, pressure == level else { return }
            guard level == .critical || content.state.browserPreferences.resourcePolicy == .conservative else { return }
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
