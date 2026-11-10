import SwiftUI

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
            if enabled.isEmpty, !manager.busy {
                Text("No extensions yet.").font(.system(size: 13)).foregroundStyle(.secondary)
            }
            ForEach(enabled) { item in
                Button { open(item) } label: {
                    HStack(spacing: 8) {
                        ChromiumExtensionIcon(item: item, size: 20)
                        Text(item.name).font(.system(size: 13)).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).disabled(item.popup == nil)
            }
            if let issue { Text(issue).font(.system(size: 12)).foregroundStyle(.red) }
            HStack {
                Button("Get Extensions") { dismiss(); commands?.openInNewTab("https://chromewebstore.google.com/") }
                Spacer()
                Button("Manage") { state.settingsCategory = .extensions; dismiss(); commands?.openPage(.settings) }
            }
            .controlSize(.small)
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
