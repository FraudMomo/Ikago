import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings ▸ Import & Export: Ikago's bookmarks, history and (if chosen) passwords in formats other browsers import
/// (`BrowserExport`), so leaving Ikago never means losing anything.
struct BrowserExportSection: View {
    let state: BrowserState
    @State private var includePasswords = false
    @State private var status: String?
    @State private var exported: URL?
    @State private var working = false
    private var vault: PasswordVault { .shared }

    var body: some View {
        PageSection(title: "Export", footer: "Files you export aren’t encrypted. Delete one with passwords as soon as it’s imported.") {
            PageRow(title: "Bookmarks", subtitle: "A bookmarks file every browser imports, with its folders") {
                Button("Export…") { exportBookmarks() }.disabled(state.bookmarks.isEmpty || working)
            }
            PageDivider()
            PageRow(title: "Bookmarks and history", subtitle: "One file Safari and Chrome import, in Safari’s export format") {
                Button("Export…") { Task { await exportAll() } }.disabled(working)
            }
            PageDivider()
            PageRow(title: "Include passwords", subtitle: vault.logins.isEmpty ? "No passwords saved in Ikago"
                    : "\(vault.logins.count) saved in Ikago; Touch ID or your password confirms the export") {
                Toggle("Include passwords", isOn: $includePasswords).labelsHidden().toggleStyle(.switch)
                    .disabled(vault.logins.isEmpty)
            }
            if let status {
                PageDivider()
                HStack(spacing: 10) {
                    Text(status).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    if let exported {
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([exported]) }
                    }
                }
                .padding(.vertical, 12)
            }
        }
    }

    private func savePanel(_ name: String, types: [UTType]) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.allowedContentTypes = types
        panel.prompt = "Export"
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func exportBookmarks() {
        guard let url = savePanel("Ikago Bookmarks.html", types: [.html]) else { return }
        do {
            try BrowserExport.save(Data(BrowserExport.bookmarksHTML(state.bookmarks, folders: state.bookmarkFolders).utf8), to: url)
            exported = url
            status = "Exported \(state.bookmarks.count) bookmarks to “\(url.lastPathComponent)”."
        } catch {
            exported = nil
            status = "Not exported: \(error.localizedDescription)"
        }
    }

    private func exportAll() async {
        guard let url = savePanel("Ikago Export.zip", types: [.zip]) else { return }
        working = true
        defer { working = false }
        do {
            var passwords: String?
            var count = 0
            if includePasswords, !vault.logins.isEmpty {
                let plain = try await vault.passwords(for: vault.logins, reason: "export your passwords to a file")
                passwords = BrowserExport.passwordsCSV(plain.map { login, password in
                    .init(title: login.title ?? login.site, url: "https://" + login.site, username: login.username, password: password)
                })
                count = plain.count
            }
            let data = BrowserExport.archive(bookmarks: BrowserExport.bookmarksHTML(state.bookmarks, folders: state.bookmarkFolders),
                                             history: BrowserExport.historyJSON(state.history), passwords: passwords)
            try BrowserExport.save(data, to: url)
            exported = url
            status = "Exported \(state.bookmarks.count) bookmarks, \(state.history.count) history pages"
                + (count > 0 ? " and \(count) passwords" : "") + " to “\(url.lastPathComponent)”."
                + (count > 0 ? " It holds the passwords in plain text: delete it once they’re imported." : "")
                + " In Safari: File ▸ Import From ▸ File or Folder. In Chrome: Settings ▸ Import Bookmarks and Settings."
        } catch {
            exported = nil
            status = "Not exported: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
        }
    }
}
