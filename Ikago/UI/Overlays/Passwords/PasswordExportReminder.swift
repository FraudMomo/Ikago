import SwiftUI

/// Once a week, while some passwords are saved only in Ikago, a card suggests exporting them to Apple Passwords (so
/// they reach iCloud Keychain and other devices). Not Now waits another week; Don't Remind Me turns it off, which
/// Settings ▸ Passwords can undo.
@MainActor
@Observable
final class PasswordExportReminder {
    static let shared = PasswordExportReminder()
    private(set) var showing = false
    private(set) var count = 0
    @ObservationIgnored private var task: Task<Void, Never>?
    private static let interval: TimeInterval = 7 * 24 * 3600
    private let defaults = UserDefaults.standard

    var enabled: Bool {
        get { defaults.object(forKey: "passwordExportReminder") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "passwordExportReminder"); if !newValue { showing = false } }
    }

    /// Checks shortly after launch and every few hours while Ikago runs.
    func start() {
        guard task == nil, !WebProfiles.isTestMode else { return }
        task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(45))
            while !Task.isCancelled {
                self?.check()
                try? await Task.sleep(for: .seconds(6 * 3600))
            }
        }
    }

    func check(now: Date = Date()) {
        guard enabled, !showing else { return }
        let last = defaults.object(forKey: "passwordExportReminderShown") as? Date ?? .distantPast
        guard now.timeIntervalSince(last) >= Self.interval else { return }
        let pending = PasswordVault.shared.unexported.count
        guard pending > 0 else { return }
        count = pending
        withAnimation(.ikago) { showing = true }
    }

    func notNow() {
        defaults.set(Date(), forKey: "passwordExportReminderShown")
        withAnimation(.ikago) { showing = false }
    }

    func neverRemind() {
        enabled = false
        withAnimation(.ikago) { showing = false }
    }

    /// Opens Settings ▸ Passwords, where the export is.
    func openExport(_ state: BrowserState, commands: BrowserCommands?) {
        notNow()
        state.settingsCategory = .passwords
        commands?.openPage(.settings)
    }
}

struct PasswordExportReminderCard: View {
    let reminder: PasswordExportReminder
    let state: BrowserState
    weak var commands: BrowserCommands?

    var body: some View {
        let colors = state.palette
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "key.icloud").font(.system(size: 18)).foregroundStyle(Color.settingsAccent)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(reminder.count) password\(reminder.count == 1 ? " is" : "s are") only in Ikago")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Export them to Apple Passwords to keep them in iCloud Keychain and on your other devices.")
                        .font(.system(size: 12)).foregroundStyle(colors.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 8) {
                Button("Don’t Remind Me") { reminder.neverRemind() }.buttonStyle(.plain)
                    .font(.system(size: 12)).foregroundStyle(colors.secondary)
                Spacer()
                Button("Not Now") { reminder.notNow() }.buttonStyle(SettingsButtonStyle())
                Button("Export…") { reminder.openExport(state, commands: commands) }.buttonStyle(SettingsButtonStyle(prominent: true))
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 360)
        .foregroundStyle(colors.text)
        .modalSurface(colors, radius: Radius.card)
    }
}
