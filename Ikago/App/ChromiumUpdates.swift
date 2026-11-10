import AppKit

/// What the background updater (`scripts/auto_update.py`) is doing, and the app's side of it. Building
/// happens outside the app, so an update never slows browsing or depends on Ikago being open.
@MainActor
@Observable
final class ChromiumUpdates {
    static let shared = ChromiumUpdates()

    struct Status: Decodable {
        var state: String?
        var pinned: String?
        var latest: String?
        var message: String?
        var checkedAt: Double?
    }

    private(set) var status = Status()
    private(set) var isEnabled = true
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private weak var window: NSWindow?

    private static let label = "app.ikago.updater"
    private var directory: URL { AppIdentity.updatesDirectory }
    private var disabledFile: URL { directory.appending(path: "disabled") }

    var isReady: Bool { status.state == "ready" }
    var summary: String {
        if !isEnabled { return "Off. Chromium stays on \(CEFVersion.chromium) until you turn this on or rebuild Ikago." }
        if let message = status.message { return message }
        return "Checks for new Chromium releases, then builds, tests and installs them automatically."
    }

    func start(window: NSWindow?) {
        self.window = window
        refresh()
        guard task == nil, !WebProfiles.isTestMode else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1800))
                self?.refresh()
                self?.offerRelaunchOnce()
            }
        }
        offerRelaunchOnce()
    }

    func refresh() {
        isEnabled = !FileManager.default.fileExists(atPath: disabledFile.path)
        guard let data = try? Data(contentsOf: directory.appending(path: "status.json")),
              let decoded = try? JSONDecoder().decode(Status.self, from: data) else { return }
        status = decoded
    }

    func setEnabled(_ enabled: Bool) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if enabled { try? FileManager.default.removeItem(at: disabledFile) }
        else { try? Data().write(to: disabledFile) }
        refresh()
    }

    func checkNow() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? Data().write(to: directory.appending(path: "check-now"))
        Self.kickUpdater()
    }

    /// Quits normally so the session saves, then the updater installs the staged build and reopens Ikago.
    func relaunchToInstall() {
        try? Data().write(to: directory.appending(path: "relaunch-after-install"))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.2; done; /bin/launchctl kickstart \"gui/$2/\(Self.label)\"", "sh",
                             String(ProcessInfo.processInfo.processIdentifier), String(getuid())]
        try? process.run()
        NSApp.terminate(nil)
    }

    private static func kickUpdater() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["kickstart", "gui/\(getuid())/\(label)"]
        try? process.run()
    }

    /// A security update shouldn't wait for someone to open Settings, but it asks only once per version.
    private func offerRelaunchOnce() {
        guard isReady, BrowserRuntime.runs(.chromium), let window, window.attachedSheet == nil, let version = status.latest else { return }
        let key = "ChromiumUpdateOffered"
        guard UserDefaults.standard.string(forKey: key) != version else { return }
        UserDefaults.standard.set(version, forKey: key)
        let alert = NSAlert()
        alert.messageText = "A Chromium security update is ready"
        alert.informativeText = "Chromium \(version) has been built and tested. Relaunch to install it, or it installs the next time you quit Ikago."
        alert.addButton(withTitle: "Relaunch Now")
        alert.addButton(withTitle: "Later")
        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertFirstButtonReturn { MainActor.assumeIsolated { self?.relaunchToInstall() } }
        }
    }
}
