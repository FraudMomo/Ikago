import Foundation

/// Checks once a minute, using the same eligibility rules for manual Debug checks.
@MainActor
final class TabHibernation {
    private weak var content: WebContentViewController?
    private var task: Task<Void, Never>?
    private var lastUsed: [String: Date] = [:]

    init(content: WebContentViewController) {
        self.content = content
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled, let self else { return }
                self.check()
            }
        }
    }

    deinit { task?.cancel() }

    func markVisible() {
        guard let content else { return }
        let live = Set(content.state.tabs.map(\.id))
        lastUsed = lastUsed.filter { live.contains($0.key) }
        for id in content.state.visibleTabIDs { lastUsed[id] = Date() }
    }

    func check(now: Date = Date()) {
        guard let content, !content.state.isFrozen else { return }
        let state = content.state
        let settings = state.browserPreferences.validated
        guard settings.hibernationEnabled else { return }
        for controller in content.controllers.values {
            let tab = controller.tab
            let protected = state.visibleTabIDs.contains(tab.id) || tab.isLoading || tab.isPlayingAudio
                || tab.cameraActive || tab.microphoneActive || (settings.protectPinnedTabs && tab.pinned)
                || settings.protects(tab.url)
            if protected { lastUsed[tab.id] = now; continue }
            guard controller.page != nil, AddressResolver.isWebURL(tab.url) else { continue }
            guard let last = lastUsed[tab.id] else { lastUsed[tab.id] = now; continue }
            if now.timeIntervalSince(last) >= Double(settings.hibernationMinutes) * 60 {
                controller.hibernate()
            }
        }
    }
}
