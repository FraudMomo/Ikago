import AppKit
import SwiftUI

/// Settings ▸ About for a downloaded Ikago: automatic updates (Sparkle), and the open-source licenses it ships.
struct AppUpdateRows: View {
    private var updates: AppUpdates { .shared }

    var body: some View {
        // An update the card offered and that wasn't installed (Later): it stays here until it is.
        if let update = updates.prompt.available {
            PageRow(title: "Ikago \(update.version) is available", subtitle: availableSubtitle(update)) {
                HStack(spacing: 8) {
                    Circle().fill(Color.settingsAccent).frame(width: 8, height: 8).accessibilityHidden(true)
                    if let page = update.downloadPage {
                        Button("Download") { NSWorkspace.shared.open(page) }.buttonStyle(SettingsButtonStyle(prominent: true))
                    } else {
                        // A user-initiated check brings the update card back, already downloaded if it was.
                        Button("Update") { updates.checkForUpdates(nil) }
                            .buttonStyle(SettingsButtonStyle(prominent: true)).disabled(!updates.canCheck)
                    }
                }
            }
            PageDivider()
        }
        PageRow(title: "Check for updates automatically", subtitle: subtitle) {
            HStack(spacing: 8) {
                Button("Check Now") { updates.checkForUpdates(nil) }.disabled(!updates.canCheck)
                Toggle("Check for updates automatically", isOn: Binding(get: { updates.checksAutomatically },
                                                                        set: { updates.setChecksAutomatically($0) }))
                    .labelsHidden().toggleStyle(.switch)
            }
        }
        PageDivider()
        PageRow(title: "Install updates automatically", subtitle: "Downloads in the background and installs the next time Ikago restarts") {
            Toggle("Install updates automatically", isOn: Binding(get: { updates.installsAutomatically },
                                                                  set: { updates.setInstallsAutomatically($0) }))
                .labelsHidden().toggleStyle(.switch).disabled(!updates.checksAutomatically)
        }
    }

    private func availableSubtitle(_ update: UpdateSummary) -> String {
        let first = update.notes.first { !$0.contains("Download needed") }
        return update.kind + (first.map { " · " + String($0.prefix(120)) } ?? "")
    }

    private var subtitle: String {
        let base = "Ikago and its Chromium engine, signed and checked before they install"
        guard let last = updates.lastCheck else { return base }
        return base + " · last checked \(last.formatted(.relative(presentation: .named)))"
    }
}

/// The licenses bundled with Ikago (Contents/Resources/Acknowledgements), each opening in a new tab.
struct AcknowledgementsSection: View {
    let state: BrowserState

    var body: some View {
        let files = Self.files
        if !files.isEmpty {
            PageSection(title: "Acknowledgements", footer: "Ikago is open source under the MIT License and builds on these projects.") {
                ForEach(Array(files.enumerated()), id: \.element) { index, file in
                    if index > 0 { PageDivider() }
                    PageRow(title: file.deletingPathExtension().lastPathComponent) {
                        Button("View") { state.newTab(url: file.absoluteString) }
                    }
                }
            }
        }
    }

    private static var files: [URL] {
        guard let folder = Bundle.main.resourceURL?.appending(path: "Acknowledgements", directoryHint: .isDirectory) else { return [] }
        let order = ["Ikago License", "Third-Party Notices", "Chromium Credits", "CEF License", "SVT-AV1 License",
                     "SVT-AV1 Patent License", "Sparkle License"]
        let found = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return found.sorted { (order.firstIndex(of: $0.deletingPathExtension().lastPathComponent) ?? 99)
            < (order.firstIndex(of: $1.deletingPathExtension().lastPathComponent) ?? 99) }
    }
}
