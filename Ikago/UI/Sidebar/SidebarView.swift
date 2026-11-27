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
            let shortcuts = state.browserPreferences.sidebarShortcuts == true
            if shortcuts && state.browserPreferences.sidebarSpaceName != false { SidebarSpaceHeader(state: state, commands: commands) }
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
            // The pinned grid goes below the shortcuts, or above them when chosen (Settings ▸ Sidebar).
            let gridAbove = shortcuts && state.browserPreferences.pinnedGridAboveShortcuts == true
            if shortcuts && !gridAbove { SidebarShortcuts(state: state, chrome: chrome, commands: commands) }
            SpaceSwipeContent(swipe: chrome.spaceSwipe, width: CGFloat(state.sidebarWidth)) {
                VStack(alignment: .leading, spacing: 10) {
                    SidebarEssentials(state: state, chrome: chrome, commands: commands)
                    PinnedGroupRows(state: state, chrome: chrome, commands: commands)
                    if gridAbove { SidebarShortcuts(state: state, chrome: chrome, commands: commands) }
                    // The native list (lift-to-reorder); the SwiftUI list stays only for "Keep pinned tabs and groups in view",
                    // which pins the top part above the scrolling list.
                    Group {
                        if state.browserPreferences.pinnedRowsStayInView == true {
                            TabListView(state: state, chrome: chrome, colors: colors, commands: commands)
                        } else {
                            SidebarOutlineList(state: state, chrome: chrome, colors: colors, commands: commands)
                        }
                    }
                    .id(state.activeSpaceID).transition(.opacity.combined(with: .offset(x: 18)))
                }
            }

            if state.showsBookmarksBar && !state.showsSidebarTopTabs { SidebarBookmarksDrawer(state: state, chrome: chrome, commands: commands) }
            SidebarMediaPlayer(state: state, commands: commands)
            let extraGroups = state.addsTabGroupsButton(in: .sidebarBottomTrailing)
            if !state.visibleChromeItems(state.chromeLayout.bottomItems).isEmpty || extraGroups {
                // Left, centre and right groups, as placed in Settings ▸ Sidebar & Toolbar ▸ Customize; the centre stays
                // centred whatever the sides hold.
                ZStack {
                    HStack(spacing: 0) {
                        controls(state.visibleChromeItems(state.chromeLayout.bottomLeading), colors, height: 36, dots: true)
                        Spacer(minLength: 0)
                        controls(state.visibleChromeItems(state.chromeLayout.bottomTrailing) + (extraGroups ? [.tabGroups] : []),
                                 colors, height: 36, dots: true)
                    }
                    controls(state.visibleChromeItems(state.chromeLayout.sidebarBottom), colors, height: 36, dots: true)
                }
                .frame(height: 36)
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

    /// The traffic lights, then the customizable controls, in one row that never slides under the lights. When the
    /// controls don't fit at full size they get smaller; when they still don't fit, the plain buttons move into a
    /// "More" menu at the end. Controls that anchor a popover (Downloads, Devices, Spaces, Share, Site Info) stay.
    private func topRow(_ colors: Palette) -> some View {
        let layout = state.chromeLayout
        let leading = state.visibleChromeItems(layout.topLeading), center = state.visibleChromeItems(layout.topCenter)
        var trailing = state.visibleChromeItems(layout.sidebarTop)
        if (DownloadCenter.shared.showsToolbarButton || chrome.showDownloads) && !layout.contains(.downloads) {
            trailing.append(.downloads)
        }
        let all = leading + center + trailing
        let fitsFull = all.count <= Self.topRowCapacity(state: state)
        let compactFit = Self.topRowCapacity(state: state, step: Self.compactStep)
        let size: CGFloat = fitsFull ? 28 : Self.compactSize
        return Group {
            if fitsFull || all.count <= compactFit {
                // Left, centre and right groups; all of them start after the traffic lights, never under them.
                // Each group in its own stack, so an empty one still holds its slot.
                ThreeSlotLayout {
                    HStack(spacing: 0) { controls(leading, colors, size: size) }
                    HStack(spacing: 0) { controls(center, colors, size: size) }
                    HStack(spacing: 0) { controls(trailing, colors, size: size) }
                }
                .frame(maxWidth: .infinity)
                .padding(.leading, leading.isEmpty && center.isEmpty ? 0 : Self.lightsReserve(state: state))
            } else {
                let split = Self.overflow(all, slots: compactFit - 1)
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    controls(split.shown, colors, size: size, more: split.more)
                }
            }
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
        let lightsInSidebar = !state.sidebarOnRight || state.sidebarLightsFollow
        return lightsInSidebar ? max(0, 79 + 8 - CGFloat(state.frameInset) - 10) : 0
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
        let lightsInSidebar = !state.sidebarOnRight || state.sidebarLightsFollow
        // The lights end 79 pt into the window (19 pt + three 14 pt buttons 9 pt apart); keep 8 pt clear of them.
        let reserved = lightsInSidebar ? max(0, 79 + 8 - inset - 10) : 0
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
            if let tab, tab.isLoading || (hovering && state.chromeLayout.addressShowsReload) {
                PageLoadButton(tab: tab, colors: colors, commands: commands)
            }
            if state.chromeLayout.addressShowsSiteInfo, hovering || SiteInfoButton.isShown(commands) {
                SiteInfoButton(state: state, colors: colors, commands: commands)
                    .transition(.opacity.combined(with: .scale(scale: 0.7)))
            }
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
