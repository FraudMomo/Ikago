import SwiftUI

/// Top Tabs: the bar between the tab row and the page, the top of the page's own card. The address spans a quiet field
/// between the controls placed on its left and right (Settings ▸ Sidebar & Toolbar ▸ Customize); the
/// Sidebar layout's bar above the page holds the address alone. It sits in its own host (`IsolatedHost`):
/// it follows the active page's address and progress, which the rest of the window doesn't need to hear about.
struct TabsToolbar: View {
    let state: BrowserState
    let chrome: ChromeModel
    let palette: CommandPaletteModel
    weak var commands: BrowserCommands?
    /// The Sidebar layout's bar above the page: the address only (its controls are the address field's own).
    var addressOnly = false

    var body: some View {
        let colors = state.palette
        let layout = state.chromeLayout
        // Above the page in the Sidebar layout the bar is the address alone; the sidebar keeps the controls.
        let leading = addressOnly ? [] : state.visibleChromeItems(layout.toolbarLeading)
        var trailing = addressOnly ? [] : state.visibleChromeItems(layout.toolbarTrailing)
        if !addressOnly, (DownloadCenter.shared.showsToolbarButton || chrome.showDownloads) && !layout.contains(.downloads, in: .toolbarTrailing) {
            trailing.append(.downloads)
        }
        // The address spans the bar between the controls, each side only as wide as its own controls.
        return HStack(spacing: 10) {
            controls(leading, colors)
            TabsAddressField(state: state, chrome: chrome, palette: palette, commands: commands)
                .frame(maxWidth: .infinity)
            controls(trailing, colors)
        }
        .padding(.horizontal, 8)
        .frame(height: state.tabsToolbarHeight)
        .background(WindowDragArea())
        .environment(\.colorScheme, colors.isDark ? .dark : .light)
        .animation(.ikagoQuick, value: trailing)
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

/// The address: at rest the whole address from the start (Full Width), or the page's title and site with the address
/// on hover (Page Title); the full field while editing.
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
                    // From the field's start, clear of the controls inside it at the end.
                    .padding(.leading, style == .title ? 8 : 12)
                    .padding(.trailing, controlsRoom)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transition(.opacity)
                // Beside the address button, not inside it: as part of its label or overlay the address button took
                // the click (and started editing) instead of these.
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    AddressFieldControls(state: state, colors: colors, commands: commands, hovering: hovering)
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
    /// Room at the field's end for the controls inside it.
    private var controlsRoom: CGFloat { max(64, CGFloat(state.chromeLayout.address.count) * 28 + 8) }

    @ViewBuilder private func restingLabel(_ tab: TabItem?, colors: Palette) -> some View {
        if let tab {
            switch style {
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
                Text("\(Text(full[..<range.upperBound]).foregroundStyle(colors.text.opacity(0.92)))\(Text(full[range.upperBound...]).foregroundStyle(colors.secondary))")
            } else {
                Text(full).foregroundStyle(colors.text.opacity(0.88))
            }
        }
        .fadeTruncated()
        .transition(.opacity)
    }
}
