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
            // Not while the address bar sits above the page (`showsPageAddressBar`).
            if state.chromeLayout.sidebarShowsAddress && !state.showsPageAddressBar {
                if chrome.isEditingAddress(of: state.activeTabID) {
                    InlineAddressField(model: palette, fontSize: 13, alignment: .left, commands: commands)
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                        .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(colors.selected))
                        .addressInteractionRegion()
                        .overlay(alignment: .bottom) { PageLoadProgress(tab: state.activeTab, colors: colors).padding(.horizontal, 10) }
                } else {
                    AddressField(state: state, colors: colors, commands: commands)
                }
            }
            SpaceSwipeContent(swipe: chrome.spaceSwipe, width: CGFloat(state.sidebarWidth)) {
                // One list: pins above the essentials, the essentials' row (the grid), groups, tabs. With nothing
                // above them, the essentials' band reaches up into the space over them, where a tab is dropped to go
                // above them; with pins above, it is the space between those and the grid.
                SidebarOutlineList(state: state, chrome: chrome, colors: colors, commands: commands)
                    .padding(.top, state.pinnedTabs.contains(where: \.pinAboveGrid) ? 0 : -SidebarEssentials.band)
                    .padding(.horizontal, -SidebarOutlineList.margin)
                    .id(state.activeSpaceID).transition(.opacity.combined(with: .offset(x: 18)))
            }

            if state.showsBookmarksBar && !state.showsSidebarTopTabs { SidebarBookmarksDrawer(state: state, chrome: chrome, commands: commands) }
            SidebarMediaPlayer(state: state, commands: commands)
            // The bottom row, centred, as placed in Settings ▸ Sidebar & Toolbar ▸ Customize.
            let bottom = state.visibleChromeItems(state.chromeLayout.sidebarBottom)
                + (state.addsTabGroupsButton(in: .sidebarBottom) ? [.tabGroups] : [])
            if !bottom.isEmpty {
                controls(bottom, colors, height: 36, dots: true)
                    .frame(maxWidth: .infinity).frame(height: 36)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, max(0, 8 - state.frameInset))  // top row stays level with the traffic lights
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            WindowDragArea()  // empty sidebar space moves the window
            SidebarSpaceSwipe(state: state, swipe: chrome.spaceSwipe)
        }
        .ignoresSafeArea(.container, edges: .top)  // the top row shares the traffic-light row
        .animation(.ikago, value: state.chromeLayout)
        .animation(.ikago, value: state.showsBookmarksBar)
    }

    /// The traffic lights, then the customizable controls at the row's end, never under the lights. When the
    /// controls don't fit at full size they get smaller; when they still don't fit, the plain buttons move into a
    /// "More" menu at the end. Controls that anchor a popover (Downloads, Devices, Spaces, Share, Site Info) stay.
    private func topRow(_ colors: Palette) -> some View {
        let layout = state.chromeLayout
        var all = state.visibleChromeItems(layout.sidebarTop)
        if (DownloadCenter.shared.showsToolbarButton || chrome.showDownloads) && !layout.contains(.downloads) {
            all.append(.downloads)
        }
        let fitsFull = all.count <= Self.topRowCapacity(state: state)
        let compactFit = Self.topRowCapacity(state: state, step: Self.compactStep)
        let size: CGFloat = fitsFull ? 28 : Self.compactSize
        let split = fitsFull || all.count <= compactFit ? (shown: all, more: []) : Self.overflow(all, slots: compactFit - 1)
        return HStack(spacing: 0) {
            Spacer(minLength: 0)
            controls(split.shown, colors, size: size, more: split.more)
        }
        .frame(height: BrowserState.sidebarRowHeight)
    }

    private static let compactSize: CGFloat = 24
    private static let compactStep: CGFloat = 26

    /// Keeps popover-anchoring controls and as many others as fit, in their order; the rest go to the More menu.
    static func overflow(_ items: [ChromeItem], slots: Int) -> (shown: [ChromeItem], more: [ChromeItem]) {
        let anchored = items.filter(\.anchorsPopover)
        let room = max(0, slots - anchored.count)
        let kept = Set(items.filter { !$0.anchorsPopover }.prefix(room))
        return (items.filter { $0.anchorsPopover || kept.contains($0) }, items.filter { !$0.anchorsPopover && !kept.contains($0) })
    }

    /// Room the traffic lights take at the start of the sidebar's top row.
    static func lightsReserve(state: BrowserState) -> CGFloat {
        max(0, 79 + 8 - CGFloat(state.frameInset) - 10)
    }

    @ViewBuilder private func controls(_ items: [ChromeItem], _ colors: Palette, height: CGFloat = 34, dots: Bool = false,
                                       size: CGFloat = 28, more: [ChromeItem] = []) -> some View {
        if !items.isEmpty || !more.isEmpty {
            GlassControlGroup(colors: colors, height: height) {
                HStack(spacing: dots ? 4 : 2) {
                    ForEach(items) { item in
                        ChromeItemView(item: item, state: state, colors: colors, commands: commands, size: size, spacesAsDots: dots)
                    }
                    if !more.isEmpty {
                        ChromeOverflowMenu(items: more, state: state, colors: colors, commands: commands, size: size)
                    }
                }
            }
        }
    }

    /// How many controls (28 pt plus spacing by default) fit between the traffic lights and the sidebar's trailing edge.
    static func topRowCapacity(state: BrowserState, step: CGFloat = 30) -> Int {
        let content = CGFloat(state.sidebarWidth) - 20  // the sidebar's horizontal padding
        let inset = CGFloat(state.frameInset)
        // The lights end 79 pt into the window (19 pt + three 14 pt buttons 9 pt apart); keep 8 pt clear of them.
        let reserved = max(0, 79 + 8 - inset - 10)
        return max(1, Int((content - reserved - 8 + 2) / step))
    }
}

/// The address field: the current site, with a hairline progress bar while loading.
struct AddressField: View {
    let state: BrowserState
    let colors: Palette
    weak var commands: BrowserCommands?
    @State private var hovering = false

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
            AddressFieldControls(state: state, colors: colors, commands: commands, hovering: hovering)
        }
        .font(.system(size: 13, weight: .medium))
        .padding(.leading, 12).padding(.trailing, 7).frame(height: 36)
        // Glass as a layer behind the field: wrapped around it, it hides the field's interaction region.
        .background {
            let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
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
