import AppKit
import SwiftUI

/// Extensions on the Chromium engine, managed entirely from here.
struct CEFExtensionsSection: View {
    let state: BrowserState
    weak var commands: BrowserCommands?
    private var manager: ChromiumExtensions { .shared }
    private var profile: String { state.activeSpace.profileID }
    @State private var link = ""

    var body: some View {
        PageSection(title: "Add Extensions") {
            PageRow(title: "Chrome Web Store", subtitle: "Open an extension and click “Add to Ikago”") {
                Button("Open Chrome Web Store") { commands?.openInNewTab("https://chromewebstore.google.com/") }
            }
            PageDivider()
            PageRow(title: "From a Web Store link") {
                HStack(spacing: 8) {
                    TextField("chromewebstore.google.com/detail/…", text: $link).textFieldStyle(.roundedBorder).frame(minWidth: 220, maxWidth: 300)
                        .onSubmit(addFromStore)
                    Button("Add", action: addFromStore).buttonStyle(.borderedProminent).disabled(link.isEmpty || manager.busy)
                }
            }
            PageDivider()
            PageRow(title: "From a folder", subtitle: "For extensions you are developing") {
                Button("Choose Folder…", action: addFromFolder).disabled(manager.busy)
            }
        }
        .disabled(state.isPrivate)
        PageSection(title: "Installed",
                    footer: "Extension popups open from the site menu in the address field.") {
            if manager.busy && manager.items.isEmpty {
                HStack(spacing: 10) { ProgressView().controlSize(.small); Text("Loading extensions…").foregroundStyle(.secondary) }.padding(18)
            } else if manager.items.isEmpty {
                VStack(spacing: 10) {
                    IconTile(symbol: "puzzlepiece.extension.fill", tint: SettingsCategory.extensions.tint, size: 46)
                    Text("No extensions yet").font(.system(size: 14, weight: .semibold))
                    Text("The ones you add appear here.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).padding(26)
            } else {
                ForEach(Array(manager.items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { PageDivider() }
                    ChromiumExtensionRow(item: item, profile: profile)
                }
            }
            if let issue = manager.issue {
                PageDivider()
                Label(issue, systemImage: "exclamationmark.triangle.fill").font(.system(size: 12)).foregroundStyle(.red).padding(14)
            }
        }
        .task(id: profile) {
            if !state.isPrivate { await manager.sync(profile: profile) }
        }
    }

    private func addFromStore() {
        let text = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        Task {
            await manager.install(storeLink: text.contains("://") || WebStoreInstaller.isValidID(text) ? text : "https://" + text, profile: profile)
            if manager.issue == nil { link = "" }
        }
    }

    private func addFromFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Add Extension"
        panel.message = "Choose a folder containing manifest.json"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        Task { await manager.install(folder: folder, profile: profile) }
    }
}

private struct ChromiumExtensionRow: View {
    let item: ChromiumExtensions.Item
    let profile: String
    @State private var confirmRemove = false

    var body: some View {
        HStack(spacing: 12) {
            ChromiumExtensionIcon(item: item, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name).font(.system(size: 14, weight: .medium)).lineLimit(1)
                    Text(item.version).font(.system(size: 11)).foregroundStyle(.tertiary)
                }
                if !item.summary.isEmpty { Text(item.summary).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2) }
            }
            Spacer(minLength: 8)
            Toggle("Enabled", isOn: Binding(get: { item.enabled }, set: { value in
                Task { await ChromiumExtensions.shared.setEnabled(item, enabled: value, profile: profile) }
            })).labelsHidden().toggleStyle(.switch)
            Button { confirmRemove = true } label: { Image(systemName: "trash") }
                .help("Remove \(item.name)").accessibilityLabel("Remove \(item.name)")
                .confirmationDialog("Remove \(item.name)?", isPresented: $confirmRemove) {
                    Button("Remove Extension", role: .destructive) {
                        Task { await ChromiumExtensions.shared.remove(item, profile: profile) }
                    }
                } message: { Text("Its saved data is deleted too.") }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .opacity(item.enabled ? 1 : 0.6)
    }
}

struct ChromiumExtensionIcon: View {
    let item: ChromiumExtensions.Item
    var size: CGFloat = 20
    var body: some View {
        if let icon = item.icon {
            Image(nsImage: icon).resizable().interpolation(.high).frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        } else {
            IconTile(symbol: "puzzlepiece.extension.fill", tint: SettingsCategory.extensions.tint, size: size)
        }
    }
}
