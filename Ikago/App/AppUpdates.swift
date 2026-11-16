import AppKit
import Sparkle

/// Updates for downloaded copies of Ikago, through Sparkle: a daily check of the signed feed on GitHub, a download
/// verified against the public key in Info.plist, then an install when Ikago restarts. Only builds made by
/// `scripts/release.py` carry the feed; builds made on this Mac update through `ChromiumUpdates` instead.
@MainActor @Observable
final class AppUpdates: NSObject, NSMenuItemValidation {
    static let shared = AppUpdates()

    private(set) var canCheck = false
    private(set) var lastCheck: Date?
    private(set) var checksAutomatically = false
    private(set) var installsAutomatically = false
    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    /// A release build with a feed and the key its updates are signed with.
    static var isAvailable: Bool {
        guard !WebProfiles.isTestMode, let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String else { return false }
        return feed.hasPrefix("https://") && !key.isEmpty
    }

    func start() {
        guard Self.isAvailable, controller == nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        let updater = controller.updater
        refresh(updater)
        observations = [
            updater.observe(\.canCheckForUpdates) { [weak self] updater, _ in Task { @MainActor in self?.refresh(updater) } },
            updater.observe(\.lastUpdateCheckDate) { [weak self] updater, _ in Task { @MainActor in self?.refresh(updater) } },
        ]
    }

    private func refresh(_ updater: SPUUpdater) {
        canCheck = updater.canCheckForUpdates
        lastCheck = updater.lastUpdateCheckDate
        checksAutomatically = updater.automaticallyChecksForUpdates
        installsAutomatically = updater.automaticallyDownloadsUpdates
    }

    func setChecksAutomatically(_ on: Bool) {
        guard let updater = controller?.updater else { return }
        updater.automaticallyChecksForUpdates = on
        refresh(updater)
    }

    func setInstallsAutomatically(_ on: Bool) {
        guard let updater = controller?.updater else { return }
        updater.automaticallyDownloadsUpdates = on
        refresh(updater)
    }

    @objc func checkForUpdates(_ sender: Any?) { controller?.checkForUpdates(sender) }

    nonisolated func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        MainActor.assumeIsolated { canCheck }
    }
}
