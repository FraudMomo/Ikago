import AppKit
import LocalAuthentication
import SwiftUI
import UniformTypeIdentifiers

/// Settings ▸ Passwords: where logins come from, importing into Ikago's vault, and managing it.
struct PasswordSettingsSection: View {
    @Bindable var state: BrowserState
    @State private var vault = PasswordVault.shared
    @State private var status: String?
    @State private var confirmingDeleteAll = false
    @State private var filter = ""
    /// Sites and usernames stay hidden until Touch ID or the Mac password.
    @State private var unlocked = false

    private var webKit: Bool { BrowserRuntime.runs(.webkit) }
    private var source: PasswordSource { PasswordSource.current }

    var body: some View {
        PageSection(title: "AutoFill", footer: footer) {
            PageRow(title: "Fill passwords", subtitle: "Show a key in sign-in fields") {
                Toggle("Fill passwords", isOn: Binding(get: { state.browserPreferences.passwordAutoFill ?? true },
                                                       set: { state.browserPreferences.passwordAutoFill = $0 }))
                    .labelsHidden().toggleStyle(.switch)
            }
            if webKit {
                PageDivider()
                PageRow(title: "Fill from", subtitle: "Chromium always uses Ikago Passwords") {
                    Picker("Fill from", selection: Binding(get: { source },
                                                          set: { state.browserPreferences.passwordSource = $0.rawValue })) {
                        Text("Ikago Passwords").tag(PasswordSource.ikago)
                        Text("Apple Passwords").tag(PasswordSource.apple)
                    }
                    .labelsHidden().fixedSize()
                }
            }
        }
        PageSection(title: "Import from Apple Passwords",
                    footer: "In the Passwords app, choose File ▸ Export All Passwords… and save the file, then import it here. Ikago encrypts every password to this Mac’s Secure Enclave, then offers to erase the exported file, because it holds your passwords in plain text. Passkeys and verification codes can’t be exported, so they stay in Apple Passwords.") {
            PageRow(title: "Passwords app", subtitle: "Export your passwords to a file first") {
                Button("Open Passwords") { openPasswordsApp() }
            }
            PageDivider()
            PageRow(title: "Exported file", subtitle: status ?? "A .csv file from Apple Passwords or Chrome") {
                Button("Import…") { importFile() }.buttonStyle(.borderedProminent)
            }
        }
        PageSection(title: "Saved in Ikago", footer: "Usernames and sites are encrypted on disk, and each password needs Touch ID or your Mac password every time it’s filled. Nothing is synced or sent anywhere. Ikago doesn’t offer to save new passwords yet.") {
            if let issue = vault.loadIssue {
                Text(issue).font(.system(size: 13)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            } else if vault.logins.isEmpty {
                Text("No passwords yet.").font(.system(size: 13)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            } else if !unlocked {
                PageRow(title: "\(vault.logins.count) password\(vault.logins.count == 1 ? "" : "s")", subtitle: "Locked") {
                    Button("Show…") { unlock() }
                }
            } else {
                PageRow(title: "\(vault.logins.count) password\(vault.logins.count == 1 ? "" : "s")", subtitle: "Search by site or username") {
                    TextField("Search", text: $filter).textFieldStyle(.roundedBorder).frame(maxWidth: 200)
                }
                ForEach(shown) { login in
                    PageDivider()
                    LoginRow(login: login) { remove([login.id]) }
                }
                if matching.count > Self.listLimit {
                    PageDivider()
                    Text("Showing \(Self.listLimit) of \(matching.count). Search to find the others.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                }
                PageDivider()
                HStack {
                    Spacer()
                    Button("Delete All Passwords…", role: .destructive) { confirmingDeleteAll = true }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
            }
        }
        .onAppear { vault.loadIfNeeded(force: true) }  // opening Settings retries a vault that failed to open
        .onDisappear { unlocked = false; filter = "" }
        .confirmationDialog("Delete all \(vault.logins.count) passwords saved in Ikago?", isPresented: $confirmingDeleteAll) {
            Button("Delete All", role: .destructive) { deleteAll() }
        } message: {
            Text("They’re removed from this Mac and can’t be recovered. Apple Passwords isn’t affected.")
        }
    }

    private var footer: String {
        if source == .apple {
            return "The key opens Apple Passwords, where you confirm with Touch ID and choose a login; Apple types it into the page, and Ikago never sees it."
        }
        return "The key lists your saved logins for the site. Pick one and confirm with Touch ID; Ikago fills it into that page only."
    }

    private static let listLimit = 200

    private var matching: [PasswordVault.Login] {
        let query = filter.trimmingCharacters(in: .whitespaces).lowercased()
        let sorted = vault.logins.sorted { ($0.site, $0.username) < ($1.site, $1.username) }
        return query.isEmpty ? sorted : sorted.filter { $0.site.contains(query) || $0.username.lowercased().contains(query) }
    }

    private var shown: [PasswordVault.Login] { Array(matching.prefix(Self.listLimit)) }

    private func openPasswordsApp() {
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Passwords") {
            NSWorkspace.shared.openApplication(at: app, configuration: .init())
        }
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.message = "Choose the file you exported from the Passwords app. Ikago offers to erase it after importing."
        panel.prompt = "Import"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let result = try PasswordImport.parse(String(contentsOf: url, encoding: .utf8))
            let count = try vault.add(result.logins)
            if !webKit || state.browserPreferences.passwordSource == nil { state.browserPreferences.passwordSource = PasswordSource.ikago.rawValue }
            var message = "Imported \(count) password\(count == 1 ? "" : "s")"
            if result.skipped > 0 { message += ", skipped \(result.skipped) without a website" }
            if confirmErase(count: count, skipped: result.skipped) {
                do { try PasswordImport.erase(url); message += ". The exported file was erased." } catch {
                    message += ". The exported file couldn’t be erased; delete it yourself."
                }
            } else { message += ". The exported file was kept; delete it when you’re done, because it holds your passwords in plain text." }
            status = message
        } catch {
            status = "Nothing was imported: \(error.localizedDescription)"
        }
    }

    /// The export is the person's only plain-text copy of anything Ikago skipped, so erasing is their call.
    private func confirmErase(count: Int, skipped: Int) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Imported \(count) password\(count == 1 ? "" : "s"). Erase the exported file?"
        var text = "It holds your passwords in plain text, so any app you run could read it."
        if skipped > 0 {
            text += " \(skipped) entr\(skipped == 1 ? "y" : "ies") without a website, such as notes or Wi-Fi networks, weren’t imported and would be erased with it. They stay in the app you exported from."
        }
        alert.informativeText = text
        alert.addButton(withTitle: "Erase File")
        alert.addButton(withTitle: "Keep File")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func unlock() {
        let context = LAContext()
        Task { @MainActor in
            defer { context.invalidate() }
            if (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "show your saved passwords")) == true {
                unlocked = true
            }
        }
    }

    private func remove(_ ids: Set<UUID>) {
        do { try vault.delete(ids) } catch { status = error.localizedDescription }
    }

    private func deleteAll() {
        do { try vault.deleteAll() } catch { status = error.localizedDescription }
    }
}

private struct LoginRow: View {
    let login: PasswordVault.Login
    let delete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(login.site).font(.system(size: 13)).lineLimit(1)
                Text(login.username.isEmpty ? "No username" : login.username).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Button("Delete", role: .destructive, action: delete).controlSize(.small).opacity(hovering ? 1 : 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu { Button("Delete", role: .destructive, action: delete) }
    }
}
