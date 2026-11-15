import AppKit
import SwiftUI
import WebKit

/// The button that appears when hovering the address: opens the site card (`SiteInfoCard`, over the window).
struct SiteInfoButton: View {
    let state: BrowserState
    let colors: Palette
    weak var commands: BrowserCommands?
    var symbol = "puzzlepiece.extension"
    @State private var hovering = false

    /// Whether the window's site card is open (keeps the button on screen while it is).
    static func isShown(_ commands: BrowserCommands?) -> Bool {
        #if DEBUG
        if DebugEnvironment.value("IKAGO_SITE_BUTTON_SHOWN") != nil { return true }  // click checks can't hover
        #endif
        return (commands as? BrowserWindowController)?.chrome.showSiteInfo == true
    }

    var body: some View {
        let shown = Self.isShown(commands)
        Button { (commands as? BrowserWindowController)?.toggleSiteInfo() } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(shown ? colors.text : colors.secondary)
                .frame(width: 22, height: 22)
                .background(Circle().fill(colors.hover.opacity(shown ? 2.2 : hovering ? 1.4 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.ikagoQuick, value: hovering)
        .animation(.ikagoQuick, value: shown)
        .help("Site settings and extensions")
    }
}

extension BrowserWindowController {
    /// Opens the site card under its button, or closes it. Sidebar + Tabs: the button sits at the end of the address
    /// bar, whose frame the shell knows. Elsewhere: where the pointer is (a button's action runs after its click event,
    /// so `NSApp.currentEvent` isn't the click any more).
    func toggleSiteInfo() {
        if chrome.showSiteInfo { chrome.showSiteInfo = false; return }
        if state.showsSidebarTopTabs, let field = chrome.addressFieldFrame {
            chrome.siteInfoAnchor = CGPoint(x: field.maxX - 15, y: field.maxY - 2)
        } else if let window, let height = window.contentView?.bounds.height {
            let point = window.mouseLocationOutsideOfEventStream
            chrome.siteInfoAnchor = CGPoint(x: point.x, y: height - point.y)
        }
        chrome.showSiteInfo = true
    }
}

/// The site card over the window, hanging below the button that opened it; a click outside or Esc closes it.
/// It grows out of its button on a short spring, as a popover does, and shrinks back into it.
struct SiteInfoOverlay: View {
    let state: BrowserState
    let chrome: ChromeModel
    weak var commands: BrowserCommands?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var contentHeight: CGFloat = 420

    static let width: CGFloat = 340

    var body: some View {
        GeometryReader { geometry in
            let width = Self.width
            let anchor = chrome.siteInfoAnchor
            // Centred on its button, as a popover hangs from its arrow: the card reaches out to the right of the bar.
            let x = min(max(12, anchor.x - width / 2), geometry.size.width - width - 12)
            let origin = UnitPoint(x: min(1, max(0, (anchor.x - x) / width)), y: 0)
            // Never past the window's bottom: a card taller than the room left scrolls inside its surface.
            let room = max(200, geometry.size.height - anchor.y - 12 - 14)
            ZStack(alignment: .topLeading) {
                Color.clear.contentShape(Rectangle()).onTapGesture { close() }
                ScrollView {
                    card.onGeometryChange(for: CGFloat.self, of: \.size.height) { contentHeight = $0 }
                }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(width: width, height: min(contentHeight, room))
                    .modalSurface(state.palette, frosted: state.frostedChrome, tint: 0.12)
                    .offset(x: x, y: anchor.y + 12)
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .scale(scale: 0.6, anchor: origin).combined(with: .opacity)
                            .animation(.spring(duration: 0.32, bounce: 0.22)),
                        removal: .scale(scale: 0.85, anchor: origin).combined(with: .opacity)
                            .animation(.spring(duration: 0.18, bounce: 0))))
            }
        }
        .onExitCommand(perform: close)
    }

    private var card: some View {
        SiteInfoCard(state: state, commands: commands, dismiss: close)
            .environment(\.siteCardTranslucent, state.palette.glass || state.frostedChrome)
            .padding(16).frame(width: Self.width)
    }

    private func close() { chrome.showSiteInfo = false }
}

/// The site card: the site and its connection, the page tools, its settings (camera, microphone, engine, tracker blocking, keep
/// awake, zoom), then extensions, and Clear Site Data.
private struct SiteInfoCard: View {
    let state: BrowserState
    weak var commands: BrowserCommands?
    let dismiss: () -> Void
    private var manager: ExtensionManager { .shared }

    var body: some View {
        let tab = state.activeTab
        let url = tab.flatMap { URL(string: $0.url) }
        let colors = state.palette
        VStack(alignment: .leading, spacing: 12) {
            if let tab { siteHeader(tab, colors: colors) }
            if let tab, AddressResolver.isWebURL(tab.url) {
                SitePageActions(state: state, commands: commands, dismiss: dismiss)
                SiteSettingsCard(state: state, tab: tab, commands: commands)
            }
            VStack(alignment: .leading, spacing: 6) {
                SiteCardHeading(title: "Extensions", colors: colors)
                if (tab?.engine ?? BrowserRuntime.engine) == .chromium {
                    CEFExtensionControls(state: state, commands: commands, dismiss: dismiss)
                } else {
                    VStack(spacing: 0) {
                        if manager.loaded.isEmpty {
                            Text("No extensions yet").font(.system(size: 13)).foregroundStyle(colors.secondary)
                                .frame(maxWidth: .infinity, minHeight: 40)
                        }
                        ForEach(manager.loaded, id: \.uniqueIdentifier) { context in
                            ExtensionRow(context: context, url: url, revision: manager.revision) {
                                dismiss()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                    context.performAction(for: commands?.activeExtensionTab)
                                }
                            }, reload: { commands?.activeExtensionTab?.page?.reload() })
                        }
                    }
                    .siteCard(colors)
                    SiteCardFooter(colors: colors) {
                        dismiss(); commands?.openInNewTab("https://chromewebstore.google.com/")
                    } manage: {
                        state.settingsCategory = .extensions; dismiss(); commands?.openPage(.settings)
                    }
                }
            }
        }
        .foregroundStyle(colors.text)
        .environment(\.colorScheme, colors.isDark ? .dark : .light)
    }

    private func siteHeader(_ tab: TabItem, colors: Palette) -> some View {
        let page = InternalPage(url: tab.url)
        let security = PageSecurity(tab)
        return HStack(spacing: 11) {
            FaviconView(tab: tab, size: 20)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(colors.text.opacity(0.06)))
            VStack(alignment: .leading, spacing: 2) {
                Text(page?.title ?? AddressResolver.hostname(tab.url)).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                if page != nil {
                    Text("Ikago page").font(.system(size: 12)).foregroundStyle(colors.secondary)
                } else {
                    Label(security == .secure ? "Connection is secure" : security == .mixed ? "Partly insecure content" : "Not secure",
                          systemImage: security == .secure ? "lock.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(security == .secure ? colors.secondary : Color.orange)
                }
            }
            Spacer(minLength: 0)
            ModalCloseButton(colors: colors, action: dismiss)
        }
    }
}

/// A small uppercase label over a card.
struct SiteCardHeading: View {
    let title: String
    let colors: Palette
    var body: some View {
        Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(colors.secondary)
            .textCase(.uppercase).tracking(0.4).padding(.leading, 4)
    }
}

/// Get Extensions and Manage under the extension list.
struct SiteCardFooter: View {
    let colors: Palette
    let get: () -> Void
    let manage: () -> Void
    var body: some View {
        HStack {
            Button("Get Extensions", action: get)
            Spacer()
            Button("Manage", action: manage)
        }
        .buttonStyle(ModalButtonStyle(colors: colors))
        .controlSize(.small)
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

#if DEBUG
/// The card's content on its own, for the `siteinfoshot` test action (a popover's window can't be captured).
@MainActor
enum SiteInfoPopoverPreview {
    static func view(state: BrowserState, commands: BrowserCommands?) -> AnyView {
        AnyView(SiteInfoCard(state: state, commands: commands) {}
            .padding(16).frame(width: SiteInfoOverlay.width)
            .modalSurface(Palette(colors: state.activeSpace.resolvedColors, isDark: state.isDark, glass: false)).padding(30))  // glass can't render offscreen
    }
}
#endif
