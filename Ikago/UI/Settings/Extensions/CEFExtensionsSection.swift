import AppKit
import SwiftUI

// MARK: - Chromium extensions section

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
                    Button("Add", action: addFromStore).buttonStyle(SettingsButtonStyle(prominent: true)).disabled(link.isEmpty || manager.busy)
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
                Label(issue, systemImage: "exclamationmark.triangle.fill").font(.system(size: 12)).foregroundStyle(.red).padding(.vertical, 14)
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
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row
            if expanded, let descriptor = ChromiumExtensions.shared.accessDescriptors.first(where: { $0.key == ChromiumExtensions.accessKey(item) })
                ?? (item.abilities.isEmpty ? nil : ExtensionDescriptor(key: ChromiumExtensions.accessKey(item), name: item.name, engine: .chromium,
                                                                      icon: item.icon, patterns: [], abilities: item.abilities)) {
                ExtensionAccessDetails(ext: descriptor).transition(.opacity)
            }
        }
    }

    private var row: some View {
        HStack(spacing: 12) {
            ExtensionDetailsButton(expanded: $expanded).padding(.trailing, -6)
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
        .padding(.vertical, 12)
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

// MARK: - Chromium extension controls

/// The site menu's extension list on the Chromium engine.
struct CEFExtensionControls: View {
    let state: BrowserState
    weak var commands: BrowserCommands?
    var dismiss: () -> Void = {}
    private var manager: ChromiumExtensions { .shared }
    @State private var issue: String?

    var body: some View {
        if state.isPrivate {
            Text("Extensions are unavailable in private windows.").font(.system(size: 13)).foregroundStyle(.secondary)
        } else {
            let enabled = manager.items.filter(\.enabled)
            VStack(spacing: 0) {
                if enabled.isEmpty, !manager.busy {
                    Text("No extensions yet.").font(.system(size: 13)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                ForEach(Array(enabled.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { SiteCardDivider() }
                    CEFExtensionRow(item: item, url: state.activeTab.flatMap { URL(string: $0.url) },
                                    reload: { commands?.activeExtensionTab?.page?.reload() }) { open(item) }
                }
            }
            .siteCard(state.palette)
            if let issue { Text(issue).font(.system(size: 12)).foregroundStyle(.red) }
            SiteCardFooter(colors: state.palette) {
                dismiss(); commands?.openInNewTab("https://chromewebstore.google.com/")
            } manage: {
                state.settingsCategory = .extensions; dismiss(); commands?.openPage(.settings)
            }
            .task(id: state.activeSpace.profileID) { await manager.refresh(profile: state.activeSpace.profileID) }
        }
    }

    private func open(_ item: ChromiumExtensions.Item) {
        guard let anchor = ExtensionManager.shared.anchors["address"] else { return }
        dismiss()
        let profile = state.activeSpace.profileID
        let tab = state.activeTab.flatMap { AddressResolver.isPageURL($0.url) ? (url: $0.url, title: $0.title) : nil }
        // Let this popover close first so the extension's popup can take its place.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            try? ChromiumExtensionPopup.show(item, profile: profile, tab: tab, relativeTo: anchor) { hard in
                NSApp.sendAction(hard ? #selector(BrowserWindowController.hardReloadPage(_:)) : #selector(BrowserWindowController.reloadPage(_:)), to: nil, from: nil)
            }
        }
    }
}

/// One Chromium extension in the site popover: its icon and name; a click opens its popup.
private struct CEFExtensionRow: View {
    let item: ChromiumExtensions.Item
    var url: URL? = nil
    var reload: () -> Void = {}
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ChromiumExtensionIcon(item: item, size: 20).frame(width: 24, height: 24)
                Text(item.name).font(.system(size: 13)).lineLimit(1)
                Spacer(minLength: 0)
                if item.popup != nil {
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                        .opacity(hovering ? 1 : 0)
                }
            }
            .padding(.horizontal, 10).frame(minHeight: 44)
            .background(Color.primary.opacity(hovering ? 0.06 : 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(SiteCardPressStyle(scale: 0.98)).allowsHitTesting(item.popup != nil)  // no popup: nothing to open, but the name stays readable
        .onHover { hovering = $0 }
        .animation(.ikagoQuick, value: hovering)
        .overlay(alignment: .trailing) {
            if let descriptor = ChromiumExtensions.shared.accessDescriptors.first(where: { $0.key == ChromiumExtensions.accessKey(item) }) {
                ExtensionSiteAccessControl(ext: descriptor, url: url, reload: reload).padding(.trailing, 10)
            }
        }
    }
}
