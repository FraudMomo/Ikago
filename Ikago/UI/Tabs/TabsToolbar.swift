import SwiftUI

/// Top Tabs: the bar between the tab row and the page, the top of the page's own card. The address sits centred
/// in a quiet field between the controls placed on its left and right (Settings ▸ Sidebar & Toolbar ▸ Customize). It sits in its own host (`IsolatedHost`):
/// it follows the active page's address and progress, which the rest of the window doesn't need to hear about.
struct TabsToolbar: View {
    let state: BrowserState
    let chrome: ChromeModel
    let palette: CommandPaletteModel
    weak var commands: BrowserCommands?
    /// The Sidebar layout's bar above the page: the address and the controls placed beside it (`pageBar*` zones).
    var addressOnly = false

    var body: some View {
        let colors = state.palette
        let layout = state.chromeLayout
        // Above the page in the Sidebar layout the bar has its own two places (Customize), the sidebar keeping the rest.
        let leading = state.visibleChromeItems(addressOnly ? layout.pageBarLeading : layout.toolbarLeading)
        var trailing = state.visibleChromeItems(addressOnly ? layout.pageBarTrailing : layout.toolbarTrailing)
        let nearLeading = addressOnly ? [] : state.visibleChromeItems(layout.toolbarNearLeading)
        let nearTrailing = addressOnly ? [] : state.visibleChromeItems(layout.toolbarNearTrailing)
        if !addressOnly, (DownloadCenter.shared.showsToolbarButton || chrome.showDownloads)
            && !ChromeZone.toolbarRow.contains(where: { layout.contains(.downloads, in: $0) }) {
            trailing.append(.downloads)
        }
        // Four places: the window's edges, and either side of the address. Each pair takes the same width on both
        // sides, so the address stays centred on the page.
        let pad: CGFloat = colors.glass ? 8 : 0
        let side = CGFloat(max(leading.count, trailing.count)) * 30 + pad
        let near = nearLeading.isEmpty && nearTrailing.isEmpty ? 0 : CGFloat(max(nearLeading.count, nearTrailing.count)) * 30 + pad
        // Centered keeps the address over the middle of the page; Full Width and Page Title let it span the bar between
        // the controls, each side only as wide as its own controls.
        let centered = state.tabsAddressStyle == .centered
        return HStack(spacing: 10) {
            controls(leading, colors).frame(width: centered ? side : nil, alignment: .leading)
            HStack(spacing: 8) {
                if !nearLeading.isEmpty || (centered && near > 0) {
                    controls(nearLeading, colors).frame(width: centered ? near : nil, alignment: .trailing)
                }
                TabsAddressField(state: state, chrome: chrome, palette: palette, commands: commands)
                    .frame(maxWidth: centered ? 680 : .infinity)
                if !nearTrailing.isEmpty || (centered && near > 0) {
                    controls(nearTrailing, colors).frame(width: centered ? near : nil, alignment: .leading)
                }
            }
            .frame(maxWidth: centered ? 680 + 2 * (near + 8) : .infinity)
            .frame(maxWidth: .infinity)
            controls(trailing, colors).frame(width: centered ? side : nil, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .frame(height: state.tabsToolbarHeight)
        .background(WindowDragArea())
        .environment(\.colorScheme, colors.isDark ? .dark : .light)
        .animation(.ikagoQuick, value: trailing)
        .animation(.ikagoQuick, value: nearLeading + nearTrailing)
        .recordLayout("tabs-toolbar")
    }

    /// One glass capsule per side with Liquid Glass on, like the sidebar's controls; plain icons with a soft hover fill
    /// on the flat sheet otherwise.
    @ViewBuilder private func controls(_ items: [ChromeItem], _ colors: Palette) -> some View {
        let row = HStack(spacing: state.tabsAddressStyle == .title ? 8 : 2) {
            ForEach(items) { item in
                ChromeItemView(item: item, state: state, colors: colors, commands: commands, size: min(28, state.tabsFieldHeight))
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        // Page Title keeps the bar one quiet surface: plain icons, no capsule around them.
        if colors.glass && !items.isEmpty && state.tabsAddressStyle != .title {
            GlassControlGroup(colors: colors, height: state.tabsFieldHeight) { row }
        } else {
            row.environment(\.inGlassGroup, true)
        }
    }
}

/// The address: at rest the site centred (Centered), the whole address from the start (Full Width), or the page's title
/// and site with the address on hover (Page Title); the full field while editing.
private struct TabsAddressField: View {
    let state: BrowserState
    let chrome: ChromeModel
    let palette: CommandPaletteModel
    weak var commands: BrowserCommands?
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let colors = state.palette
        let tab = state.activeTab
        let editing = chrome.isEditingAddress(of: state.activeTabID)
        let shape = RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
        ZStack {
            if editing {
                InlineAddressField(model: palette, fontSize: 13, alignment: .left, commands: commands)
                    .padding(.horizontal, 12)
                    .transition(.opacity)
            } else {
                Button { commands?.showCommandPalette(newTab: false) } label: {
                    HStack(spacing: 6) {
                        PrivateBadge(state: state, colors: colors)
                        if let tab { SecurityBadge(tab: tab, colors: colors) }
                        restingLabel(tab, colors: colors)
                    }
                    .font(.system(size: 13))
                    // Centered: clear of the buttons on the right, and still centred. Otherwise from the field's start.
                    .padding(.leading, style == .centered ? 64 : style == .title ? 8 : 12)
                    .padding(.trailing, 64)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: style == .centered ? .center : .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transition(.opacity)
                // Beside the address button, not inside it: as part of its label or overlay the address button took
                // the click (and started editing) instead of these.
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    if let tab, tab.isLoading || (hovering && state.chromeLayout.addressShowsReload) {
                        PageLoadButton(tab: tab, colors: colors, commands: commands)
                    }
                    if state.chromeLayout.addressShowsSiteInfo, hovering || SiteInfoButton.isShown(commands) {
                        SiteInfoButton(state: state, colors: colors, commands: commands)
                    }
                }
                .padding(.trailing, 4)
                .transition(.opacity)
                .help("Search or enter address (⌘L)")
            }
        }
        .frame(height: state.tabsFieldHeight)
        .background {
            if editing {
                shape.fill(colors.pageBackground)
            } else if style == .title {
                // Page Title: no field at rest, just the words on the bar; a soft fill shows it can be clicked.
                shape.fill(colors.text.opacity(hovering ? 0.06 : 0))
            } else if !colors.glass {
                shape.fill(colors.text.opacity(hovering ? 0.08 : 0.05))
            }
        }
        // At rest with Liquid Glass on, the field is a piece of glass like the controls beside it.
        .glassControl(shape, colors, active: !editing && style != .title)
        .overlay {
            // A soft accent ring while typing.
            shape.strokeBorder(colors.accent.opacity(editing ? 0.55 : 0), lineWidth: 1.5)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .bottom) { PageLoadProgress(tab: tab, colors: colors).padding(.horizontal, 10) }
        .background(ExtensionPopupAnchor())
        .anchorPreference(key: DownloadsAnchorKey.self, value: .bounds) { DownloadAnchors(address: $0) }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: hovering ? 0.1 : 0.2), value: hovering)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: editing)
        .recordLayout("tabs-address")
    }

    private var style: TabsAddressStyle { state.tabsAddressStyle }

    @ViewBuilder private func restingLabel(_ tab: TabItem?, colors: Palette) -> some View {
        if let tab {
            switch style {
            case .centered:
                Text(tab.addressLabel).lineLimit(1).truncationMode(.middle)
                    .foregroundStyle(colors.text.opacity(0.88))
                    .contentTransition(.opacity)
            case .wide:
                addressText(tab, colors: colors)
            case .title:
                // The site, then the page's title, read as one line ("site / title"); the address itself while the
                // pointer is over the field.
                if hovering || !AddressResolver.isWebURL(tab.url) {
                    addressText(tab, colors: colors)
                } else {
                    HStack(spacing: 5) {
                        Text(tab.addressLabel).foregroundStyle(colors.text.opacity(0.92)).lineLimit(1).fixedSize()
                            .layoutPriority(1)
                        if tab.displayTitle != tab.addressLabel {
                            Text("/").foregroundStyle(colors.tertiary).fixedSize()
                            Text(tab.displayTitle).foregroundStyle(colors.secondary).fadeTruncated()
                                .layoutPriority(0)
                        }
                    }
                    .transition(.opacity)
                }
            }
        } else {
            Text("Search or enter address").lineLimit(1).foregroundStyle(colors.tertiary)
        }
    }

    /// The whole address, the site strong and the rest quieter, fading out where it doesn't fit.
    private func addressText(_ tab: TabItem, colors: Palette) -> some View {
        let full = tab.shortAddress
        let host = AddressResolver.hostname(tab.url)
        let range = host.isEmpty ? nil : full.range(of: host)
        return Group {
            if let range {
                Text(full[..<range.upperBound]).foregroundStyle(colors.text.opacity(0.92))
                    + Text(full[range.upperBound...]).foregroundStyle(colors.secondary)
            } else {
                Text(full).foregroundStyle(colors.text.opacity(0.88))
            }
        }
        .fadeTruncated()
        .transition(.opacity)
    }
}
