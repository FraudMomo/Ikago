import AppKit
import SwiftUI

struct BrowserImportSection: View {
    let state: BrowserState
    @State private var showOtherOptions = false
    @State private var showDetails = false
    private var model: BrowserImportModel { state.importer }

    var body: some View {
        PageSection(title: "Import",
                    footer: "Imports into “\(state.activeSpace.name)”. Your current tabs and bookmarks are kept.") {
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
                HStack(spacing: 12) {
                    BrowserLogo(browser: profile.browser)
                    PageRow(title: profile.title, subtitle: profile.subtitle) {
                        BrowserImportButton(state: state, profile: profile) { showDetails = false }
                    }
                }
            }
        }
        .task { await model.refresh() }
        if let result = model.result {
            PageSection(title: model.accessNeededFor != nil ? "Allow Browser Access" : model.failed ? "Import Needs Attention" : "Import Complete") {
                if let report = model.report, !report.items.isEmpty {
                    // One line per kind of data: what came in, and why anything didn't.
                    ForEach(Array(report.items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { PageDivider() }
                        PageRow(title: item.kind, subtitle: item.summary) {
                            Image(systemName: item.imported == item.found ? "checkmark.circle.fill" : "checkmark.circle")
                                .foregroundStyle(item.imported > 0 ? Color.settingsAccent : .secondary)
                                .accessibilityHidden(true)
                        }
                    }
                } else {
                    Text(result).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 14)
                }
                if model.fullDiskAccessNeeded {
                    PageDivider()
                    PageRow(title: "Safari logins and open tabs",
                            subtitle: "macOS keeps these behind Full Disk Access. Turn on Ikago there, then import again.") {
                        FullDiskAccessButton()
                    }
                }
                if model.accessNeededFor != nil {
                    HStack {
                        Button("Allow Access & Retry") { Task { await model.retryWithAccess(into: state) } }
                            .buttonStyle(SettingsButtonStyle(prominent: true)).disabled(model.importingID != nil)
                        Spacer()
                    }.padding(.bottom, 16)
                }
                if !model.notes.isEmpty {
                    DisclosureGroup("Details", isExpanded: $showDetails) {
                        ForEach(Array(model.notes.enumerated()), id: \.offset) { _, note in
                            Text(note).font(.callout).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                        }
                    }.padding(.vertical, 14)
                }
            }
        }
        DisclosureGroup(isExpanded: $showOtherOptions) {
            HStack {
                Button("Import an Exported File…") { chooseFile() }.disabled(model.importingID != nil)
                Button("Refresh Browsers") { Task { await model.refresh() } }.disabled(model.importingID != nil || model.discovering)
                Spacer()
            }.padding(.top, 10)
        } label: { Text("Other Options").onTapGesture { 
            withAnimation { showOtherOptions.toggle() } 
            } }
        .font(.callout).foregroundStyle(.secondary)
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.message = "Choose a browser’s export: a ZIP, bookmarks, history, passwords or a session file"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        showDetails = false
        Task { await model.importFile(url, into: state) }
    }
}

/// Opens System Settings at Full Disk Access, the only way macOS lets Ikago read Safari's logins and open tabs.
struct FullDiskAccessButton: View {
    var prominent = false

    var body: some View {
        Button("Open Full Disk Access") { ImportAccessPrompt.openFullDiskAccess() }
        .buttonStyle(SettingsButtonStyle(prominent: prominent))
    }
}

/// Imports one detected profile; shared by Settings and the welcome page.
struct BrowserImportButton: View {
    let state: BrowserState
    let profile: DetectedBrowserProfile
    var prominent = true
    var willImport: () -> Void = {}
    private var model: BrowserImportModel { state.importer }

    var body: some View {
        HStack(spacing: 10) {
            if model.importingID == profile.id { ProgressView().controlSize(.small) }
            Button(model.importingID == profile.id ? "Importing…" : model.completed.contains(profile.id) ? "Import Again" : "Import") {
                willImport()
                Task { await model.importProfile(profile, into: state) }
            }
            .buttonStyle(SettingsButtonStyle(prominent: prominent))
            .disabled(model.importingID != nil)  // importing again only adds what is new
            .accessibilityLabel("Import from \(profile.browser), \(profile.name)")
        }
    }
}
