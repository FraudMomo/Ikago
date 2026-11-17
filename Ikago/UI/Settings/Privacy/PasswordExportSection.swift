import AppKit
import SwiftUI

/// Settings ▸ Passwords ▸ Saved: hands Apple Passwords the logins saved in Ikago that it doesn't have yet. Apple offers
/// no API for adding passwords, so this writes the Passwords app's own import format to a file the person imports
/// (File ▸ Import Passwords…), then erases it. Export All takes the logins saved here and never exported (or changed
/// since), so nothing is handed over twice; Choose… picks any of them, including imported or already exported ones.
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
                PageRow(title: count == 0 ? "Nothing new to export" : "\(count) password\(count == 1 ? "" : "s") only in Ikago",
                        subtitle: status ?? (count == 0 ? "Everything saved in Ikago is already in Apple Passwords" : "Saved in Ikago and not yet in Apple Passwords")) {
                    HStack(spacing: 8) {
                        if count > 0 { Circle().fill(Color.settingsAccent).frame(width: 8, height: 8).accessibilityHidden(true) }
                        Button("Choose…") { choosing = true }.disabled(vault.logins.isEmpty)
                        Button("Export All…") { Task { await export(vault.unexported) } }
                            .buttonStyle(SettingsButtonStyle(prominent: true)).disabled(count == 0)
                    }
                }
                PageDivider()
                PageRow(title: "Remind me to export", subtitle: "Once a week while some passwords are only in Ikago") {
                    Toggle("Remind me to export", isOn: Binding(get: { PasswordExportReminder.shared.enabled },
                                                               set: { PasswordExportReminder.shared.enabled = $0 }))
                        .labelsHidden().toggleStyle(.switch)
                }
            }
        }
        .sheet(isPresented: $choosing) {
            PasswordExportChooser { chosen in
                choosing = false
                if !chosen.isEmpty { Task { await export(chosen) } }
            }
        }
    }

    @State private var choosing = false

    private func export(_ logins: [PasswordVault.Login]) async {
        guard !logins.isEmpty else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Ikago Passwords.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.message = "Save the passwords for Apple Passwords. Ikago erases the file once you’ve imported it."
        panel.prompt = "Export"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let plain = try await vault.passwords(for: logins, reason: "export \(logins.count) password\(logins.count == 1 ? "" : "s") for Apple Passwords")
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

/// Choose which saved logins go to Apple Passwords: the ones only in Ikago are ticked; Show all lists every login.
private struct PasswordExportChooser: View {
    let done: ([PasswordVault.Login]) -> Void
    @State private var selected: Set<UUID> = Set(PasswordVault.shared.unexported.map(\.id))
    @State private var showAll = PasswordVault.shared.unexported.isEmpty
    @State private var query = ""

    var body: some View {
        let vault = PasswordVault.shared
        let pending = Set(vault.unexported.map(\.id))
        let rows = (showAll ? vault.logins : vault.logins.filter { pending.contains($0.id) })
            .filter { query.isEmpty || $0.site.localizedCaseInsensitiveContains(query) || $0.username.localizedCaseInsensitiveContains(query) }
            .sorted { $0.site < $1.site }
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose Passwords to Export").font(.system(size: 15, weight: .semibold))
            HStack {
                TextField("Search", text: $query).textFieldStyle(.roundedBorder)
                Toggle("Show all passwords", isOn: $showAll).toggleStyle(.checkbox)
            }
            List(rows) { login in
                Toggle(isOn: Binding(get: { selected.contains(login.id) },
                                     set: { on in if on { selected.insert(login.id) } else { selected.remove(login.id) } })) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(login.title ?? login.site).lineLimit(1)
                        Text(login.username + (pending.contains(login.id) ? " · only in Ikago" : ""))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .toggleStyle(.checkbox)
            }
            .frame(minHeight: 260)
            HStack {
                Button(rows.allSatisfy { selected.contains($0.id) } ? "Select None" : "Select All") {
                    if rows.allSatisfy({ selected.contains($0.id) }) { selected.subtract(rows.map(\.id)) }
                    else { selected.formUnion(rows.map(\.id)) }
                }
                Spacer()
                Button("Cancel") { done([]) }.keyboardShortcut(.cancelAction)
                Button("Export \(selected.count)…") { done(vault.logins.filter { selected.contains($0.id) }) }
                    .keyboardShortcut(.defaultAction).disabled(selected.isEmpty)
            }
        }
        .padding(18)
        .frame(width: 460, height: 440)
    }
}
