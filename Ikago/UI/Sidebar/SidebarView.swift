import SwiftUI

/// Vertical sidebar: navigation, address, pinned tiles, the Space's folders and tabs, and
/// the Space bar. Shown on a floating glass panel, docked or revealed from the edge.
struct SidebarView: View {
    let state: BrowserState
    let chrome: ChromeModel
    let palette: CommandPaletteModel
    weak var commands: BrowserCommands?

    var body: some View {
        let colors = state.palette
        VStack(alignment: .leading, spacing: 10) {
            topRow(colors)
            if state.chromeLayout.sidebarShowsAddress {
                if chrome.isEditingAddress(of: state.activeTabID) {
                    InlineAddressField(model: palette, fontSize: 13, alignment: .left, commands: commands)
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(colors.selected))
                        .addressInteractionRegion()
                        .overlay(alignment: .bottom) { PageLoadProgress(tab: state.activeTab, colors: colors).padding(.horizontal, 10) }
                } else {
                    AddressField(state: state, colors: colors, commands: commands)
                }
            }
            SidebarEssentials(state: state, chrome: chrome, commands: commands)
            TabListView(state: state, chrome: chrome, colors: colors, commands: commands)
                .overlay(alignment: .top) { EmptyEssentialsDropZone(state: state, chrome: chrome) }
            if state.showsBookmarksBar { SidebarBookmarksDrawer(state: state, chrome: chrome, commands: commands) }
            SidebarMediaPlayer(state: state, commands: commands)
            if !state.chromeLayout.sidebarBottom.isEmpty {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    GlassControlGroup(colors: colors, height: 36) {
                        HStack(spacing: 4) {
                            ForEach(state.chromeLayout.sidebarBottom) { item in
                                ChromeItemView(item: item, state: state, colors: colors, commands: commands, spacesAsDots: true)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(height: 36)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, max(0, 8 - state.frameInset))  // top row stays level with the traffic lights
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(WindowDragArea())  // empty sidebar space moves the window
        .ignoresSafeArea(.container, edges: .top)  // the top row shares the traffic-light row
        .animation(.ikago, value: state.chromeLayout)
        .animation(.ikago, value: state.showsBookmarksBar)
    }

    /// Room for the traffic lights, then the customizable controls.
    private func topRow(_ colors: Palette) -> some View {
        HStack(spacing: 2) {
            Spacer()
            if (DownloadCenter.shared.showsToolbarButton || chrome.showDownloads) && !state.chromeLayout.contains(.downloads, inTopBar: false) {
                DownloadToolbarButton(colors: colors, commands: commands)
            }
            GlassControlGroup(colors: colors, height: 34) {
                HStack(spacing: 2) {
                    ForEach(state.chromeLayout.sidebarTop) { item in
                        ChromeItemView(item: item, state: state, colors: colors, commands: commands)
                    }
                }
            }
        }
        .frame(height: 36)
    }
}

/// The address field: the current site, with a hairline progress bar while loading.
struct AddressField: View {
    let state: BrowserState
    let colors: Palette
    weak var commands: BrowserCommands?
    @State private var hovering = false
    @State private var showInfo = false

    var body: some View {
        let tab = state.activeTab
        HStack(spacing: 4) {
            Button { commands?.showCommandPalette(newTab: false) } label: {
                HStack(spacing: 7) {
                    PrivateBadge(state: state, colors: colors)
                    if let tab { SecurityBadge(tab: tab, colors: colors) }
                    Text(label(tab)).lineLimit(1).foregroundStyle(tab == nil ? colors.secondary : colors.text)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
            }.buttonStyle(.plain).help("Search or enter address (⌘L)")
            if let tab, tab.isLoading || hovering {
                PageLoadButton(tab: tab, colors: colors, commands: commands)
            }
            if hovering || showInfo {
                SiteInfoButton(state: state, colors: colors, commands: commands, isPresented: $showInfo)
                    .transition(.opacity.combined(with: .scale(scale: 0.7)))
            }
        }
        .font(.system(size: 13, weight: .medium))
        .padding(.leading, 12).padding(.trailing, 7).frame(height: 36)
        // Glass as a layer behind the field: wrapped around it, it hides the field's interaction region.
        .background {
            let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
            shape.fill(colors.glass ? .clear : colors.hover.opacity(hovering ? 1.8 : 1.2)).glassControl(shape, colors)
        }
        .overlay(alignment: .bottom) { PageLoadProgress(tab: tab, colors: colors).padding(.horizontal, 10) }
        .background(ExtensionPopupAnchor())
        .onHover { hovering = $0 }
        .animation(.ikagoQuick, value: hovering)
        .help("Search or enter address (⌘L)")
    }

    private func label(_ tab: TabItem?) -> String {
        tab?.addressLabel ?? "Search or enter address"
    }
}

/// Small borderless icon button for window chrome.
struct ChromeButton: View {
    let symbol: String
    let help: String
    let colors: Palette
    var size: CGFloat = 28
    var iconSize: CGFloat? = nil
    var enabled = true
    /// Overrides the palette's secondary ink.
    var foreground: Color?
    /// Off for small buttons inside lists, where glass on every row would be noise.
    var glass = true
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.inGlassGroup) private var inGroup

    /// This button is its own piece of glass, which answers the pointer without a separate hover fill.
    private var isGlass: Bool { glass && colors.glass && !inGroup }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: iconSize ?? (size > 26 ? 13 : 11), weight: .medium))
                .foregroundStyle(foreground ?? (colors.glass && glass ? colors.text.opacity(0.85) : colors.secondary))
                // The icon dims when disabled, not the glass under it.
                .opacity(enabled ? 1 : 0.35)
                .frame(width: size, height: size)
                .background(Circle().fill(hovering && enabled && !isGlass ? colors.hover.opacity(1.6) : .clear))
                .contentShape(Circle())
                .glassControl(Circle(), colors, active: glass, reacts: enabled)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovering = $0 }
        .animation(.ikagoQuick, value: hovering)
        .help(help)
    }
}
