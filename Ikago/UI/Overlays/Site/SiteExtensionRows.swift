import SwiftUI
import WebKit

/// An extension's access to the page's website, as a small menu at the end of its row in the site card (`ExtensionAccessMenu`).
/// Shown when the extension reads this website, or a choice was made here.
struct ExtensionSiteAccessControl: View {
    let ext: ExtensionDescriptor
    let url: URL?
    let reload: () -> Void
    private var access: ExtensionAccess { .shared }

    var body: some View {
        if let url, let site = ExtensionAccess.site(url), ext.wants(url) || access.entry(ext.key).sites[site] != nil {
            let status = access.status(ext.key, site: site)
            CompactMenu(value: ExtensionAccessMenu.label(status), choices: ExtensionAccessMenu.choices(ext, site: site) { _ in reload() })
                .help(ExtensionAccessMenu.detail(status, site: site))
        }
    }
}

/// One extension: icon, name, whether it runs on this site, and its badge.
struct SiteExtensionRow: View {
    let context: WKWebExtensionContext
    let url: URL?
    let revision: Int  // re-render when actions change
    let action: () -> Void
    var reload: () -> Void = {}
    @State private var hovering = false

    var body: some View {
        let ext = context.webExtension
        let tabAction = context.action(for: nil)
        Button(action: action) {
            HStack(spacing: 10) {
                if let icon = tabAction?.icon(for: CGSize(width: 20, height: 20)) ?? ext.icon(for: CGSize(width: 20, height: 20)) {
                    Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                } else {
                    Image(systemName: "puzzlepiece.extension.fill").frame(width: 20, height: 20)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(ext.displayName ?? "Extension").font(.system(size: 13)).lineLimit(1)
                    HStack(spacing: 4) {
                        Circle().fill(isActive ? Color.green : Color.secondary.opacity(0.5)).frame(width: 6, height: 6)
                        Text(isActive ? "Active on this site" : "Not running here").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let badge = tabAction?.badgeText, !badge.isEmpty {
                    Text(badge).font(.system(size: 10, weight: .bold)).padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                }
            }
            .padding(.horizontal, 10).frame(minHeight: 44)
            .background(Color.primary.opacity(hovering ? 0.06 : 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(SiteCardPressStyle(scale: 0.98))
        .onHover { hovering = $0 }
        .animation(.ikagoQuick, value: hovering)
        .help(tabAction?.label ?? ext.displayName ?? "")
        .overlay(alignment: .trailing) {
            if let descriptor = ExtensionManager.shared.accessDescriptors.first(where: { $0.key == context.uniqueIdentifier }) {
                ExtensionSiteAccessControl(ext: descriptor, url: url, reload: reload).padding(.trailing, 10)
            }
        }
    }

    private var isActive: Bool {
        guard let url, ["http", "https"].contains(url.scheme ?? "") else { return false }
        return context.hasInjectedContent(for: url) || (context.hasAccess(to: url) && context.hasContentModificationRules)
    }
}

