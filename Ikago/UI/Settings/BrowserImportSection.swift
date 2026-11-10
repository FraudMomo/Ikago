import AppKit
import SwiftUI

struct BrowserImportSection: View {
    let state: BrowserState
    @State private var showOtherOptions = false
    @State private var showDetails = false
    private var model: BrowserImportModel { state.importer }

    var body: some View {
        PageSection(title: "Import",
                    footer: "Import bookmarks, history, open tabs, tab groups and available website logins into “\(state.activeSpace.name)”. Chrome groups become folders. Your current tabs and bookmarks are kept. macOS may ask you to allow access.") {
            if model.discovering && model.profiles.isEmpty {
                HStack(spacing: 10) { ProgressView().controlSize(.small); Text("Finding your browsers…") }
                    .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            } else if model.profiles.isEmpty {
                PageRow(title: "No browser profiles found", subtitle: "Install or open another browser, then check again.") {
                    Button("Check Again") { Task { await model.refresh() } }
                        .disabled(model.importingID != nil)
                }
            }
            ForEach(Array(model.profiles.enumerated()), id: \.element.id) { index, profile in
                if index > 0 { PageDivider() }
                PageRow(title: profile.title, subtitle: profile.subtitle) {
                    HStack(spacing: 10) {
                        if model.importingID == profile.id { ProgressView().controlSize(.small) }
                        Button(model.completed.contains(profile.id) ? "Imported" : model.importingID == profile.id ? "Importing…" : "Import") {
                            showDetails = false
                            Task { await model.importProfile(profile, into: state) }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.importingID != nil || model.completed.contains(profile.id))
                        .accessibilityLabel("Import from \(profile.browser), \(profile.name)")
                    }
                }
            }
        }
        .task { await model.refresh() }
        if let result = model.result {
            PageSection(title: model.accessNeededFor != nil ? "Allow Browser Access" : model.failed ? "Import Needs Attention" : "Import Complete") {
                Text(result).frame(maxWidth: .infinity, alignment: .leading).padding(16)
                if model.accessNeededFor != nil {
                    HStack {
                        Button("Allow Access & Retry") { Task { await model.retryWithAccess(into: state) } }
                            .buttonStyle(.borderedProminent).disabled(model.importingID != nil)
                        Spacer()
                    }.padding(.horizontal, 16).padding(.bottom, 16)
                }
                if !model.notes.isEmpty {
                    DisclosureGroup("Details", isExpanded: $showDetails) {
                        ForEach(Array(model.notes.enumerated()), id: \.offset) { _, note in
                            Text(note).font(.callout).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                        }
                    }.padding(16)
                }
            }
        }
        DisclosureGroup("Other options", isExpanded: $showOtherOptions) {
            HStack {
                Button("Import an Exported File…") { chooseFile() }.disabled(model.importingID != nil)
                Button("Refresh Browsers") { Task { await model.refresh() } }.disabled(model.importingID != nil || model.discovering)
                Spacer()
            }.padding(.top, 10)
        }
        .font(.callout).foregroundStyle(.secondary)
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.message = "Choose bookmarks, a browser session, or a cookie export"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        showDetails = false
        Task { await model.importFile(url, into: state) }
    }
}
