import SwiftUI

/// A site's favicon, the site's /favicon.ico before the page reports one, or the symbol of
/// a Ikago page.
struct FaviconView: View {
    private let url: URL?
    private let pageURL: String
    private let symbol: String?
    @State private var cachedImage: NSImage?
    @State private var displayedSite: String
    @Environment(\.privateBrowsing) private var privateBrowsing
    /// Icons follow the mode they're drawn in: a site's dark icon, and SVG icons' own dark styles.
    @Environment(\.colorScheme) private var colorScheme
    var size: CGFloat = 16

    init(tab: TabItem, size: CGFloat = 16) {
        symbol = InternalPage(url: tab.url)?.symbol
        url = tab.faviconURL ?? Self.fallback(for: tab.url)
        pageURL = tab.url
        // An extension's page (Momentum's new tab) shows its extension's icon.
        _cachedImage = State(initialValue: ExtensionPageIcon.image(for: tab.url)
            ?? FaviconCache.shared.cachedImage(pageURL: tab.url, iconURL: url))
        _displayedSite = State(initialValue: FaviconCache.siteKey(tab.url))
        self.size = size
    }

    /// For a page URL without a live tab (history rows).
    init(pageURL: String, iconURL: String? = nil, size: CGFloat = 16) {
        self.pageURL = pageURL
        symbol = InternalPage(url: pageURL)?.symbol
        url = iconURL.flatMap(URL.init(string:)) ?? Self.fallback(for: pageURL)
        _cachedImage = State(initialValue: FaviconCache.shared.cachedImage(pageURL: pageURL, iconURL: url))
        _displayedSite = State(initialValue: FaviconCache.siteKey(pageURL))
        self.size = size
    }

    private static func fallback(for page: String) -> URL? {
        guard var parts = URLComponents(string: page), ["https", "http"].contains(parts.scheme ?? ""), parts.host != nil else { return nil }
        parts.path = "/favicon.ico"; parts.query = nil; parts.fragment = nil
        return parts.url
    }

    var body: some View {
        Group {
            if let symbol {
                Image(systemName: symbol).resizable().scaledToFit().fontWeight(.medium).foregroundStyle(.secondary)
            } else {
                if let cachedImage {
                    // Only bitmaps are rounded: clipping a symbol this way made some (clock, arrow.down.circle) vanish.
                    Image(nsImage: cachedImage).resizable().interpolation(.high)
                        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
                } else {
                    Image(systemName: "globe").resizable().scaledToFit().foregroundStyle(.secondary)
                }
            }
        }
        .task(id: pageURL + "|" + (url?.absoluteString ?? "") + "|\(colorScheme == .dark)") {
            let dark = colorScheme == .dark
            let site = FaviconCache.siteKey(pageURL)
            if let own = ExtensionPageIcon.image(for: pageURL) { cachedImage = own; displayedSite = site; return }
            let saved = FaviconCache.shared.cachedImage(pageURL: pageURL, iconURL: url, dark: dark)
            if site != displayedSite { cachedImage = saved; displayedSite = site }
            else if let saved { cachedImage = saved }
            if let url, let image = await FaviconCache.shared.image(pageURL: pageURL, iconURL: url, persist: !privateBrowsing, dark: dark), !Task.isCancelled {
                cachedImage = image
            }
        }
        .frame(width: size, height: size)
    }
}

/// One tab in the sidebar. The active tab's background slides between rows
/// (`matchedGeometryEffect`); the close button appears on hover.
struct TabRowView: View {
    let tab: TabItem
    let isActive: Bool
    let isInSplit: Bool
    let colors: Palette
    let selection: Namespace.ID
    weak var commands: BrowserCommands?
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                FaviconView(tab: tab)
                    .opacity(tab.isLoading ? 0.35 : 1)
                if tab.isLoading { ProgressView().controlSize(.mini).scaleEffect(0.7) }
            }
            .frame(width: 16, height: 16)

            Text(tab.displayTitle)
                .lineLimit(1)
                .foregroundStyle(isActive ? colors.text : colors.text.opacity(0.85))

            Spacer(minLength: 4)
            if tab.isUnloaded {
                Image(systemName: "moon.zzz").font(.system(size: 10)).foregroundStyle(colors.secondary)
            }
            TabMediaIndicators(tab: tab, colors: colors, commands: commands)
            if hovering {
                Button { withAnimation(.ikago) { commands?.closeTab(tab.id) } } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(colors.hover.opacity(1.5)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(colors.secondary)
                .help("Close Tab (⌘W)")
                .transition(.opacity.combined(with: .scale(scale: 0.7)))
            }
        }
        .font(.system(size: 13, weight: isActive ? .medium : .regular))
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background {
            TabSelectionHighlight(shape: RoundedRectangle(cornerRadius: Radius.row, style: .continuous), active: isActive,
                                  color: colors.selected, selection: selection, id: "active-tab")
            if !isActive && isInSplit {
                RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(colors.selected.opacity(0.45))
            } else if !isActive && hovering {
                RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(colors.hover)
            }
        }
        .contentShape(Rectangle())
        .tabPeek(tab, commands: commands)
        .sidebarHover($hovering)
        .animation(.ikagoQuick, value: hovering)
        .opacity(tab.isUnloaded ? 0.48 : 1)
    }
}

/// Camera / microphone in use (each a menu to mute, stop or pick the mic), and a speaker that mutes or unmutes the tab.
struct TabMediaIndicators: View {
    let tab: TabItem
    let colors: Palette
    weak var commands: BrowserCommands?

    var body: some View {
        HStack(spacing: 6) {
            if tab.cameraActive { CaptureMenu(tab: tab, microphone: false, commands: commands) }
            if tab.microphoneActive { CaptureMenu(tab: tab, microphone: true, commands: commands) }
            TabAudioButton(tab: tab, colors: colors, commands: commands)
        }
        .animation(.ikagoQuick, value: tab.isPlayingAudio)
    }
}
