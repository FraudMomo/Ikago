import AppKit
import Sparkle

/// What an update brings, read from the signed feed: the version, whether it is a security update (Sparkle's critical
/// update, which every Chromium release is), the Chromium it carries, and its changes as Markdown from BUILDS.md.
struct UpdateSummary: Equatable {
    let version: String
    let security: Bool
    let chromium: String?
    let notes: [String]
    /// An update this copy can't install by itself (`<sparkle:informationalUpdate>`): the card offers the download page.
    var downloadPage: URL? = nil

    init(_ item: SUAppcastItem) {
        version = item.displayVersionString
        security = item.isCriticalUpdate
        downloadPage = item.isInformationOnlyUpdate ? item.infoURL : nil
        let text = item.itemDescription ?? ""
        // One bullet per "- " line; an indented line continues the bullet above it.
        var bullets: [String] = []
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if line.first?.isWhitespace == true, !trimmed.hasPrefix("- "), let last = bullets.popLast() {
                bullets.append(last + " " + trimmed)
            } else {
                bullets.append(trimmed.hasPrefix("- ") ? String(trimmed.dropFirst(2)) : trimmed)
            }
        }
        notes = bullets
        let fromFeed = item.propertiesDictionary["ikago:chromium"] as? String
        chromium = fromFeed ?? text.firstMatch(of: /Chromium (\d+(?:\.\d+){1,3})/).map { String($0.1) }
    }

    init(version: String, security: Bool, chromium: String?, notes: [String], downloadPage: URL? = nil) {
        (self.version, self.security, self.chromium, self.notes) = (version, security, chromium, notes)
        self.downloadPage = downloadPage
    }

    /// What kind of update it is, for the card's label.
    var kind: String {
        switch (security, notes.contains { !$0.contains("Chromium") }) {
        case (true, true): "Security update and new features"
        case (true, false): "Security update"
        default: "New in Ikago"
        }
    }
}

/// The update card's state (`UpdateCard`), shown in the frontmost window. Each phase keeps the reply Sparkle waits for.
@MainActor @Observable
final class UpdatePrompt {
    enum Phase {
        case checking
        case found(UpdateSummary, downloaded: Bool)
        case downloading(UpdateSummary?, fraction: Double?)
        case installing(UpdateSummary?)
        case upToDate
        case failed(String)
    }

    var phase: Phase?
    /// An update that was found and not installed (Later on the card): Settings ▸ About keeps offering it.
    var available: UpdateSummary?
    @ObservationIgnored fileprivate var choose: ((SPUUserUpdateChoice) -> Void)?
    @ObservationIgnored fileprivate var cancel: (() -> Void)?
    @ObservationIgnored fileprivate var acknowledge: (() -> Void)?
    @ObservationIgnored fileprivate var relaunch: ((SPUUserUpdateChoice) -> Void)?
    @ObservationIgnored fileprivate var installChosen = false
    @ObservationIgnored fileprivate var summary: UpdateSummary?

    /// Update and Relaunch, from the card: the download (if needed) and the install go on by themselves.
    func install() {
        installChosen = true
        if let relaunch { self.relaunch = nil; return relaunch(.install) }
        choose?(.install)
        choose = nil
    }

    /// Later: Sparkle reminds again at a later check.
    func later() {
        choose?(.dismiss)
        relaunch?(.dismiss)
        cancel?()
        acknowledge?()
        clear()
    }

    /// Opens the release page for an update this copy can't install, and dismisses the card.
    func download(_ page: URL) {
        NSWorkspace.shared.open(page)
        later()
    }

    func skip() {
        choose?(.skip)
        available = nil
        clear()
    }

    fileprivate func clear() {
        (choose, cancel, acknowledge, relaunch) = (nil, nil, nil, nil)
        phase = nil
    }
}

/// Ikago's own update interface for Sparkle: the card in the window instead of Sparkle's standard windows. Sparkle still
/// does every check, download, signature verification and install; this only shows them and passes on the answers.
@MainActor
final class AppUpdateDriver: NSObject, SPUUserDriver {
    let prompt = UpdatePrompt()
    private var expected: UInt64 = 0
    private var received: UInt64 = 0

    func present(_ phase: UpdatePrompt.Phase) {
        prompt.phase = phase
        NSApp.requestUserAttention(.informationalRequest)
    }

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        // Release builds turn daily checks on in Info.plist; system profiling stays off.
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        prompt.cancel = cancellation
        prompt.phase = .checking
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        AppUpdates.prepareSparkleFolder()
        let summary = UpdateSummary(appcastItem)
        prompt.summary = summary
        prompt.cancel = nil
        prompt.choose = reply
        prompt.installChosen = false
        prompt.available = summary
        present(.found(summary, downloaded: state.stage != .notDownloaded))
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}

    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        prompt.cancel = nil
        prompt.acknowledge = acknowledgement
        prompt.available = nil
        prompt.phase = .upToDate
    }

    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        prompt.cancel = nil
        prompt.acknowledge = acknowledgement
        prompt.phase = .failed(error.localizedDescription)
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        AppUpdates.prepareSparkleFolder()
        prompt.cancel = cancellation
        (expected, received) = (0, 0)
        prompt.phase = .downloading(prompt.summary, fraction: nil)
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) { expected = expectedContentLength }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        received += length
        guard expected > 0 else { return }
        prompt.phase = .downloading(prompt.summary, fraction: min(1, Double(received) / Double(expected)))
    }

    func showDownloadDidStartExtractingUpdate() { prompt.phase = .installing(prompt.summary) }
    func showExtractionReceivedProgress(_ progress: Double) {}

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        AppUpdates.prepareSparkleFolder()  // the installer is about to create its folder there
        prompt.cancel = nil
        if prompt.installChosen { return reply(.install) }  // the person already chose Update and Relaunch
        prompt.relaunch = reply
        if let summary = prompt.summary { present(.found(summary, downloaded: true)) }
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        prompt.phase = .installing(prompt.summary)
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        acknowledgement()
        prompt.available = nil
        prompt.clear()
    }

    func showUpdateInFocus() { NSApp.activate() }

    func dismissUpdateInstallation() { prompt.clear() }
}
