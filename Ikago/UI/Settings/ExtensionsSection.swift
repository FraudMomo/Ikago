import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// Settings page section: installed extensions, enable/disable, options, removal, and
/// installing from the Chrome Web Store, a file or folder, or a Safari extension.
struct ExtensionsSection: View {
    weak var commands: BrowserCommands?
    @State private var foundSafariExtensions: [URL] = []
    private var manager: ExtensionManager { .shared }

    var body: some View {
        PageSection(title: "Extensions",
                    footer: "Extensions run in every Space. Some Chrome extensions only partly work.") {
            if let issue = manager.installIssue {
                PageRow(title: "Extension could not be added", subtitle: issue) {
                    Button("Dismiss") { manager.installIssue = nil }
                }
                PageDivider()
            }
            PageRow(title: "Automatic extension updates", subtitle: manager.updateMessage) {
                Toggle("Automatic extension updates", isOn: Binding(get: { manager.automaticUpdates }, set: { manager.automaticUpdates = $0 }))
                    .labelsHidden().toggleStyle(.switch)
            }
            ForEach(manager.updateDetails, id: \.self) { detail in
                PageRow(title: "Update unavailable", subtitle: detail) { EmptyView() }
            }
            PageDivider()
            HStack {
                Button("Check for Updates") { Task { await manager.checkForUpdates(force: true) } }
                Button("Review Updates") { Task { await manager.checkForUpdates(force: true, reviewPermissions: true) } }
            }.disabled(manager.checkingUpdates).padding(16)
            PageDivider()
            if manager.records.isEmpty {
                PageRow(title: "No extensions yet", subtitle: "Open one in the Chrome Web Store and click “Add to Ikago”.") { EmptyView() }
                PageDivider()
            }
            ForEach(manager.records) { record in
                ExtensionRow(record: record, context: manager.contexts[record.id], commands: commands)
                PageDivider()
            }
            ForEach(safariExtensions, id: \.self) { appex in
                PageRow(title: appName(appex), subtitle: "Safari extension on this Mac") {
                    Button("Add") { commands?.installSafariExtension(at: appex) }
                }
                PageDivider()
            }
            HStack(spacing: 10) {
                Button("Chrome Web Store") { commands?.openInNewTab("https://chromewebstore.google.com/") }
                Button("Install from File…") { chooseLocalPackage() }
                Spacer()
            }
            .padding(16)
        }
        .onAppear { foundSafariExtensions = ExtensionManager.safariExtensionsOnThisMac() }
    }

    /// Scanned when the section appears; ones already added are hidden.
    private var safariExtensions: [URL] {
        let added = Set(manager.records.compactMap(\.appexPath))
        return foundSafariExtensions.filter { !added.contains($0.path) }
    }

    private func appName(_ appex: URL) -> String {
        appex.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingPathExtension().lastPathComponent
    }

    private func chooseLocalPackage() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [.zip, UTType(filenameExtension: "crx") ?? .data, .folder]
        panel.message = "Choose an unpacked extension folder, or a .crx or .zip package"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        commands?.installLocalExtension(at: url)
    }
}

private struct ExtensionRow: View {
    let record: ExtensionManager.Record
    let context: WKWebExtensionContext?
    weak var commands: BrowserCommands?

    var body: some View {
        let ext = context?.webExtension
        HStack(spacing: 12) {
            if let icon = ext?.icon(for: CGSize(width: 32, height: 32)) {
                Image(nsImage: icon).resizable().frame(width: 24, height: 24)
            } else {
                Image(systemName: "puzzlepiece.extension").frame(width: 24, height: 24)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(ext?.displayName ?? record.id).lineLimit(1)
                Text(detail).font(.caption).foregroundStyle(errors.isEmpty ? Color.secondary : Color.orange).lineLimit(2)
            }
            Spacer()
            if context?.optionsPageURL != nil {
                Button("Options") {
                    if let url = context?.optionsPageURL { commands?.openInNewTab(url.absoluteString) }
                }
            }
            Toggle("", isOn: Binding(get: { record.enabled },
                                     set: { on in Task { await ExtensionManager.shared.setEnabled(record.id, on) } }))
                .labelsHidden().toggleStyle(.switch)
            Button(role: .destructive) { ExtensionManager.shared.remove(record.id) } label: { Image(systemName: "trash") }
                .controlSize(.small)
                .help("Remove")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .disabled(ExtensionManager.shared.installing.contains(record.id))
    }

    private var extManifest: [String: Any]? { context?.webExtension.manifest }

    private var errors: [Error] { (context?.webExtension.errors ?? []) + (context?.errors ?? []) }

    private var detail: String {
        if let failure = ExtensionManager.shared.failures[record.id] { return "Not supported or failed to load: \(failure)" }
        if !record.enabled { return "Off" }
        if let first = errors.first { return "Problem: \(first.localizedDescription)" }
        if let manifest = extManifest {
            let warnings = ExtensionCompatibility.warnings(manifest: manifest, safari: record.appexPath != nil)
            if !warnings.isEmpty { return "Limited support · " + warnings.joined(separator: " ") }
        }
        return "Version \(context?.webExtension.displayVersion ?? "?")\(record.fromWebStore ? " · Chrome Web Store" : "")"
    }
}
