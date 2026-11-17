import AppKit
import Sparkle

/// Updates for downloaded copies of Ikago, through Sparkle: a daily check of the signed feed on GitHub, a download
/// verified against the public key in Info.plist, then an install when Ikago restarts. Ikago shows them itself
/// (`AppUpdateDriver`, the update card) instead of Sparkle's windows. Only builds made by `scripts/release.py` carry the
/// feed; builds made on this Mac update through `ChromiumUpdates` instead.
@MainActor @Observable
final class AppUpdates: NSObject, NSMenuItemValidation {
    static let shared = AppUpdates()

    private(set) var canCheck = false
    private(set) var lastCheck: Date?
    private(set) var checksAutomatically = false
    private(set) var installsAutomatically = false
    @ObservationIgnored private var updater: SPUUpdater?
    @ObservationIgnored private let driver = AppUpdateDriver()
    /// The update card's state, shown in the frontmost window.
    var prompt: UpdatePrompt { driver.prompt }
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    /// A release build with a feed and the key its updates are signed with.
    static var isAvailable: Bool {
        guard !WebProfiles.isTestMode, let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String else { return false }
        return feed.hasPrefix("https://") && !key.isEmpty
    }

    func start() {
        guard Self.isAvailable, updater == nil else { return }
        Self.prepareSparkleFolder()
        let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: nil)
        do { try updater.start() } catch {
            NSLog("Ikago updates could not start: %@", error.localizedDescription)
            return
        }
        self.updater = updater
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
        guard let updater else { return }
        updater.automaticallyChecksForUpdates = on
        refresh(updater)
    }

    func setInstallsAutomatically(_ on: Bool) {
        guard let updater else { return }
        updater.automaticallyDownloadsUpdates = on
        refresh(updater)
    }

    @objc func checkForUpdates(_ sender: Any?) {
        Self.prepareSparkleFolder()
        updater?.checkForUpdates()
    }

    /// Sparkle keeps its downloads and its installer's working folder in `Caches/<bundle ID>/org.sparkle-project.Sparkle`.
    /// With protected storage that caches folder is a link into Ikago's app group container, which macOS locks to Ikago
    /// itself: Sparkle's installer runs as its own process and may not create anything there ("Operation not
    /// permitted", even signed with the group), so every update downloaded and then failed. Sparkle's folder becomes a
    /// link to `Caches/<bundle ID>.Updates/org.sparkle-project.Sparkle` outside the container
    /// (Sparkle's installer refuses downloads whose resolved path lacks that folder name), which the installer can use; it only ever holds
    /// signed update archives. Ikago also quarantines what it creates (`LSFileQuarantineEnabled`), so the folders lose
    /// that flag before each check and install; the update itself is verified by its signatures.
    static func prepareSparkleFolder() {
        let files = FileManager.default
        guard let caches = files.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        let app = caches.appending(path: AppIdentity.bundleID, directoryHint: .isDirectory)
        let sparkle = app.appending(path: "org.sparkle-project.Sparkle", directoryHint: .isDirectory)
        // Sparkle's installer only accepts downloads whose real path runs through a folder with Sparkle's name.
        let outside = caches.appending(path: AppIdentity.bundleID + ".Updates/org.sparkle-project.Sparkle", directoryHint: .isDirectory)
        let linked = (try? app.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
        // Only a real folder (or none) is replaced, never a link, so a download in progress is never touched.
        if linked, (try? files.destinationOfSymbolicLink(atPath: sparkle.path)) == nil {
            try? files.createDirectory(at: outside, withIntermediateDirectories: true)
            // A folder from before holds only update downloads; Sparkle fetches them again.
            try? files.removeItem(at: sparkle)
            try? files.createSymbolicLink(at: sparkle, withDestinationURL: outside)
        }
        let root = linked ? outside : sparkle
        var folders = [app, root]
        if let inside = files.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey]) {
            for case let url as URL in inside where (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                folders.append(url)
            }
        }
        for folder in folders { removexattr(folder.path, "com.apple.quarantine", 0) }
    }

    nonisolated func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        MainActor.assumeIsolated { canCheck }
    }
}
