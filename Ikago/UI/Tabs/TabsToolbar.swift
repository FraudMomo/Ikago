import SwiftUI

/// Sidebar + Tabs: the bar between the tab row and the page, the top of the page's own card. Navigation controls on the
/// left, the address centred in a quiet field, everything else on the right. It sits in its own host (`IsolatedHost`):
/// it follows the active page's address and progress, which the rest of the window doesn't need to hear about.
struct TabsToolbar: View {
    let state: BrowserState
    let chrome: ChromeModel
    let palette: CommandPaletteModel
    weak var commands: BrowserCommands?

    /// Controls that stay left of the address; the rest of the placed controls sit on the right.
    static let navigation: Set<ChromeItem> = [.sidebarToggle, .back, .forward, .reload]
    static let fieldHeight: CGFloat = 28

    var body: some View {
        let colors = state.palette
        var items = state.visibleChromeItems(state.chromeLayout.topItems)
        if (DownloadCenter.shared.showsToolbarButton || chrome.showDownloads) && !state.chromeLayout.contains(.downloads) {
            items.append(.downloads)
        }
        let leading = items.filter { Self.navigation.contains($0) }
        let trailing = items.filter { !Self.navigation.contains($0) }
        // Both sides take the same width, so the address stays centred on the page.
        let side = CGFloat(max(leading.count, trailing.count)) * 30 + (colors.glass ? 8 : 0)
        return HStack(spacing: 10) {
            controls(leading, colors).frame(width: side, alignment: .leading)
            TabsAddressField(state: state, chrome: chrome, palette: palette, commands: commands)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            controls(trailing, colors).frame(width: side, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .frame(height: BrowserState.tabsToolbarHeight)
        .background(WindowDragArea())
        .environment(\.colorScheme, colors.isDark ? .dark : .light)
        .animation(.ikagoQuick, value: trailing)
        .recordLayout("tabs-toolbar")
    }

    /// One glass capsule per side with Liquid Glass on, like the sidebar's controls; plain icons with a soft hover fill
    /// on the flat sheet otherwise.
    @ViewBuilder private func controls(_ items: [ChromeItem], _ colors: Palette) -> some View {
        let row = HStack(spacing: 2) {
            ForEach(items) { item in
                ChromeItemView(item: item, state: state, colors: colors, commands: commands)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        if colors.glass && !items.isEmpty {
            GlassControlGroup(colors: colors, height: TabsToolbar.fieldHeight) { row }
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
                    if let tab, tab.isLoading || hovering {
                        PageLoadButton(tab: tab, colors: colors, commands: commands)
                    }
                    if hovering || SiteInfoButton.isShown(commands) {
                        SiteInfoButton(state: state, colors: colors, commands: commands)
                    }
                }
                .padding(.trailing, 4)
                .transition(.opacity)
                .help("Search or enter address (⌘L)")
            }
        }
        .frame(height: TabsToolbar.fieldHeight)
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
