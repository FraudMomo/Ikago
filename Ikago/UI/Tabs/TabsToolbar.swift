import SwiftUI

/// Sidebar + Tabs: the bar between the tab row and the page, the top of the page's own card. The address sits centred
/// in a quiet field between the controls placed on its left and right (Settings ▸ Sidebar & Toolbar ▸ Customize). It sits in its own host (`IsolatedHost`):
/// it follows the active page's address and progress, which the rest of the window doesn't need to hear about.
struct TabsToolbar: View {
    let state: BrowserState
    let chrome: ChromeModel
    let palette: CommandPaletteModel
    weak var commands: BrowserCommands?

    var body: some View {
        let colors = state.palette
        let layout = state.chromeLayout
        let leading = state.visibleChromeItems(layout.toolbarLeading)
        var trailing = state.visibleChromeItems(layout.toolbarTrailing)
        let nearLeading = state.visibleChromeItems(layout.toolbarNearLeading)
        let nearTrailing = state.visibleChromeItems(layout.toolbarNearTrailing)
        if (DownloadCenter.shared.showsToolbarButton || chrome.showDownloads)
            && !ChromeZone.toolbarRow.contains(where: { layout.contains(.downloads, in: $0) }) {
            trailing.append(.downloads)
        }
        // Four places: the window's edges, and either side of the address. Each pair takes the same width on both
        // sides, so the address stays centred on the page.
        let pad: CGFloat = colors.glass ? 8 : 0
        let side = CGFloat(max(leading.count, trailing.count)) * 30 + pad
        let near = nearLeading.isEmpty && nearTrailing.isEmpty ? 0 : CGFloat(max(nearLeading.count, nearTrailing.count)) * 30 + pad
        return HStack(spacing: 10) {
            controls(leading, colors).frame(width: side, alignment: .leading)
            HStack(spacing: 8) {
                if near > 0 { controls(nearLeading, colors).frame(width: near, alignment: .trailing) }
                TabsAddressField(state: state, chrome: chrome, palette: palette, commands: commands)
                    .frame(maxWidth: 680)
                if near > 0 { controls(nearTrailing, colors).frame(width: near, alignment: .leading) }
            }
            .frame(maxWidth: 680 + 2 * (near + 8))
            .frame(maxWidth: .infinity)
            controls(trailing, colors).frame(width: side, alignment: .trailing)
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
        let row = HStack(spacing: 2) {
            ForEach(items) { item in
                ChromeItemView(item: item, state: state, colors: colors, commands: commands, size: min(28, state.tabsFieldHeight))
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        if colors.glass && !items.isEmpty {
            GlassControlGroup(colors: colors, height: state.tabsFieldHeight) { row }
        } else {
            row.environment(\.inGlassGroup, true)
        }
    }
}

/// The address, centred: the site and its security at rest, the full field while editing.
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
                        Text(tab?.addressLabel ?? "Search or enter address").lineLimit(1).truncationMode(.middle)
                            .foregroundStyle(tab == nil ? colors.tertiary : colors.text.opacity(0.88))
                            .contentTransition(.opacity)
                    }
                    .font(.system(size: 13))
                    .padding(.horizontal, 64)  // clear of the buttons on the right, and still centred
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            if editing || !colors.glass {
                shape.fill(editing ? colors.pageBackground : colors.text.opacity(hovering ? 0.08 : 0.05))
            }
        }
        // At rest with Liquid Glass on, the field is a piece of glass like the controls beside it.
        .glassControl(shape, colors, active: !editing)
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
}
