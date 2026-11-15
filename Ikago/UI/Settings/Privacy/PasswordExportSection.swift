import AppKit
import SwiftUI

/// Settings ▸ Passwords ▸ Saved: hands Apple Passwords the logins saved in Ikago that it doesn't have yet. Apple offers
/// no API for adding passwords, so this writes the Passwords app's own import format to a file the person imports
/// (File ▸ Import Passwords…), then erases it. Only logins saved here and never exported (or changed since) are
/// included, so nothing is handed over twice; imported logins came from a password manager and are left out.
struct PasswordExportSection: View {
    @State private var file: URL?
    @State private var pending: Set<UUID> = []
    @State private var status: String?
    private var vault: PasswordVault { .shared }

    var body: some View {
        let count = vault.unexported.count
        PageSection(title: "Export to Apple Passwords",
                    footer: "Passwords saved in Ikago aren’t in Apple Passwords until you export them. Each export has only the new and changed ones.") {
            if let file {
                VStack(alignment: .leading, spacing: 10) {
                    Text("In Passwords, choose File ▸ Import Passwords… and pick “\(file.lastPathComponent)”. Then come back here to erase the file, because it holds the passwords in plain text.")
                        .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Button("Open Passwords") { openPasswordsApp() }
                        Spacer()
                        Button("Cancel") { finish(imported: false) }
                        Button("Imported, Erase File") { finish(imported: true) }.buttonStyle(SettingsButtonStyle(prominent: true))
                    }
                }
                .padding(.vertical, 12)
            } else {
                PageRow(title: count == 0 ? "Nothing new to export" : "\(count) new password\(count == 1 ? "" : "s")",
                        subtitle: status ?? (count == 0 ? "Everything saved in Ikago is already exported" : "Saved in Ikago since the last export")) {
                    Button("Export…") { Task { await export() } }.buttonStyle(SettingsButtonStyle(prominent: true)).disabled(count == 0)
                }
            }
        }
    }

    private func export() async {
        let logins = vault.unexported
        guard !logins.isEmpty else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Ikago Passwords.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.message = "Save the new passwords for Apple Passwords. Ikago erases the file once you’ve imported it."
        panel.prompt = "Export"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let plain = try await vault.passwords(for: logins, reason: "export \(logins.count) new password\(logins.count == 1 ? "" : "s") for Apple Passwords")
            var csv = "Title,URL,Username,Password,Notes,OTPAuth\n"
            for (login, password) in plain {
                csv += [login.title ?? login.site, "https://" + login.site, login.username, password, "", ""].map(Self.field).joined(separator: ",") + "\n"
            }
            try? FileManager.default.removeItem(at: url)
            guard FileManager.default.createFile(atPath: url.path, contents: Data(csv.utf8), attributes: [.posixPermissions: 0o600]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            pending = Set(logins.map(\.id))
            file = url
            status = nil
            openPasswordsApp()
        } catch {
            status = (error as? LocalizedError)?.errorDescription.map { "Not exported: \($0)" } ?? status
        }
    }

    private func finish(imported: Bool) {
        guard let url = file else { return }
        if imported { try? vault.markExported(pending) }
        do {
            try PasswordImport.erase(url)
            status = imported ? "Exported and erased the file." : "Cancelled. The file was erased."
        } catch {
            status = "The file couldn’t be erased; delete “\(url.lastPathComponent)” yourself."
        }
        file = nil
        pending = []
    }

    /// RFC 4180: always quoted, quotes doubled.
    private static func field(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }

    private func openPasswordsApp() {
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Passwords") {
            NSWorkspace.shared.openApplication(at: app, configuration: .init())
        }
    }
}
