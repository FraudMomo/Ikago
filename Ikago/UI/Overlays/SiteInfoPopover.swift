import AppKit
import SwiftUI
import WebKit

/// The button that appears when hovering the address: opens site info and extensions.
struct SiteInfoButton: View {
    let state: BrowserState
    let colors: Palette
    weak var commands: BrowserCommands?
    @Binding var isPresented: Bool
    var symbol = "puzzlepiece.extension"

    var body: some View {
        Button { isPresented.toggle() } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(colors.secondary)
                .frame(width: 22, height: 22)
                .background(Circle().fill(isPresented ? colors.hover.opacity(2) : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Site and extensions")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            SiteInfoPopover(state: state, commands: commands) { isPresented = false }
        }
    }
}

/// Site details and the extensions that run on it.
private struct SiteInfoPopover: View {
    let state: BrowserState
    weak var commands: BrowserCommands?
    let dismiss: () -> Void
    private var manager: ExtensionManager { .shared }

    var body: some View {
        let tab = state.activeTab
        let url = tab.flatMap { URL(string: $0.url) }
        VStack(alignment: .leading, spacing: 14) {
            if let tab { siteHeader(tab) }
            if let tab { SiteEngineRow(state: state, tab: tab, commands: commands) }
            if let tab, tab.cameraActive || tab.microphoneActive {
                Label(tab.cameraActive && tab.microphoneActive ? "Using camera and microphone"
                      : tab.cameraActive ? "Using your camera" : "Using your microphone",
                      systemImage: tab.cameraActive ? "video.fill" : "mic.fill")
                    .font(.system(size: 12)).foregroundStyle(.red)
            }
            if let page = commands?.activeExtensionTab?.page, abs(page.zoomLevel) > 0.01 {
                HStack {
                    Text("Zoom \(Int((pow(1.2, page.zoomLevel) * 100).rounded()))%").font(.system(size: 12))
                    Spacer()
                    Button("Reset") { page.zoomLevel = 0 }.controlSize(.small)
                }
            }
            Divider()
            Text("Extensions").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            if (tab?.engine ?? BrowserRuntime.engine) == .chromium {
                CEFExtensionControls(state: state, commands: commands, dismiss: dismiss)
            } else {
            if manager.loaded.isEmpty {
                Text("No extensions yet.").font(.system(size: 13)).foregroundStyle(.secondary)
            }
            ForEach(manager.loaded, id: \.uniqueIdentifier) { context in
                ExtensionRow(context: context, url: url, revision: manager.revision) {
                    dismiss()
                    // Let our popover close first so the extension's popup can take its place.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        context.performAction(for: commands?.activeExtensionTab)
                    }
                }
            }
            HStack {
                Button("Get Extensions") { dismiss(); commands?.openInNewTab("https://chromewebstore.google.com/") }
                Spacer()
                Button("Manage") { dismiss(); commands?.openPage(.settings) }
            }
            .controlSize(.small)
            }
        }
        .padding(16)
        .frame(width: 300)
    }

    private func siteHeader(_ tab: TabItem) -> some View {
        let page = InternalPage(url: tab.url)
        let secure = PageSecurity(tab) == .secure
        return HStack(spacing: 10) {
            FaviconView(tab: tab, size: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(page?.title ?? AddressResolver.hostname(tab.url)).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                if page != nil {
                    Text("Ikago page").font(.system(size: 12)).foregroundStyle(.secondary)
                } else {
                    Label(secure ? "Secure connection" : PageSecurity(tab) == .mixed ? "Partly insecure content" : "Not secure", systemImage: secure ? "lock.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(secure ? Color.secondary : Color.orange)
                }
            }
        }
    }
}

/// One extension: icon, name, whether it runs on this site, and its badge.
private struct ExtensionRow: View {
    let context: WKWebExtensionContext
    let url: URL?
    let revision: Int  // re-render when actions change
    let action: () -> Void
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
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(hovering ? Color.primary.opacity(0.06) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(tabAction?.label ?? ext.displayName ?? "")
    }

    private var isActive: Bool {
        guard let url, ["http", "https"].contains(url.scheme ?? "") else { return false }
        return context.hasInjectedContent(for: url) || (context.hasAccess(to: url) && context.hasContentModificationRules)
    }
}

/// Put behind the address field: extension popups point at it.
struct ExtensionPopupAnchor: FillingViewRepresentable {
    var identifier = "address"
    func makeNSView(context: Context) -> NSView {
        ExtensionAnchorView(identifier: identifier)
    }

    func updateNSView(_ view: NSView, context: Context) {
        (view as? ExtensionAnchorView)?.anchorIdentifier = identifier
        (view as? ExtensionAnchorView)?.publish()
    }
    static func dismantleNSView(_ view: NSView, coordinator: ()) {
        for key in Array(ExtensionManager.shared.anchors.keys) where ExtensionManager.shared.anchors[key] === view {
            ExtensionManager.shared.anchors.removeValue(forKey: key)
        }
    }
}

private final class ExtensionAnchorView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    var anchorIdentifier: String {
        didSet {
            if oldValue != anchorIdentifier, ExtensionManager.shared.anchors[oldValue] === self {
                ExtensionManager.shared.anchors.removeValue(forKey: oldValue)
            }
        }
    }
    init(identifier: String) { self.anchorIdentifier = identifier; super.init(frame: .zero) }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); publish() }
    func publish() {
        if window != nil { ExtensionManager.shared.anchors[anchorIdentifier] = self }
        else if ExtensionManager.shared.anchors[anchorIdentifier] === self { ExtensionManager.shared.anchors.removeValue(forKey: anchorIdentifier) }
    }
}
