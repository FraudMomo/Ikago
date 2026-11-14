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
            VStack(spacing: 0) {
                if enabled.isEmpty, !manager.busy {
                    Text("No extensions yet.").font(.system(size: 13)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                ForEach(Array(enabled.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { SiteCardDivider() }
                    CEFExtensionRow(item: item) { open(item) }
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
    }
}
