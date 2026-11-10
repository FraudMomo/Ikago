import AppKit
import SwiftUI

/// The whole window below the titlebar: sidebar or top bar, the web content card, and the
/// floating layer (peeked sidebar, command bar, find bar, split targets). One SwiftUI tree,
/// so Liquid Glass samples the page behind it and everything animates together.
struct BrowserRootView: View {
    let state: BrowserState
    let chrome: ChromeModel
    let palette: CommandPaletteModel
    let find: FindBarModel
    let content: NSView
    weak var commands: BrowserCommands?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The docked sidebar stays mounted while it slides out, then leaves the tree.
    @State private var sidebarMounted = true

    var body: some View {
        let colors = state.palette
        ZStack(alignment: .topLeading) {
            if state.tabLayout == .vertical {
                HStack(spacing: 0) {
                    if docksSidebar || sidebarMounted {
                        Group {
                            if state.showsSidebarRail {
                                SidebarRail(state: state, commands: commands)
                                    .transition(.opacity)
                            } else {
                                IsolatedHost(chrome: chrome) {
                                    SidebarView(state: state, chrome: chrome, palette: palette, commands: commands)
                                }
                                .frame(width: state.sidebarWidth)
                                .transition(.opacity)
                            }
                        }
                        .frame(width: sidebarShownWidth, alignment: .leading)
                        // Full screen: the panel runs to the top, its contents start below the menu bar.
                        .padding(.top, state.isImmersive ? state.immersiveChromeTop : 0)
                        .clipped()
                        .sidebarPanel(colors, radius: radius, translucent: state.browserPreferences.translucentSidebar == true)
                        .padding([.leading, .top, .bottom], inset)
                        // Hiding narrows this frame with the panel pinned to its trailing edge, so the panel slides out
                        // beside the page. A transition can't move the AppKit views inside it; they would only fade.
                        .frame(width: docksSidebar ? sidebarShownWidth + inset : 0, alignment: .trailing)
                        .clipped()
                        .allowsHitTesting(docksSidebar)
                    }
                    if docksSidebar {
                        // The gap between sidebar and page is the resize handle (the rail has a fixed width).
                        if state.showsSidebarRail { Color.clear.frame(width: state.sidebarGap) } else {
                            SidebarResizeHandle(state: state, width: state.sidebarGap)
                        }
                    }
                    contentCard(for: .vertical).padding(.leading, docksSidebar ? 0 : inset)
                }
            } else {
                VStack(spacing: 0) {
                    if !state.barFloating && !state.isImmersive { topBar }
                    contentCard(for: .horizontal).padding(.leading, inset)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .overlay(alignment: .top) {
                    if state.isImmersive {
                        TopBarReveal(state: state, chrome: chrome, palette: palette, commands: commands)
                    } else if state.barFloating {
                        topBar
                    }
                }
            }
            if state.tabLayout == .vertical && !docksSidebar {
                SidebarPeek(state: state, chrome: chrome, palette: palette, commands: commands)
            }
            overlays
            if state.tabLayout.usesTopTabs, chrome.showTabOverview {
                TemporaryTabSidebar(state: state, chrome: chrome, palette: palette, commands: commands)
            }
        }
        .environment(\.tabHighlightStyle, state.tabHighlightStyle)
        .recordLayout("shell")
        .overlayPreferenceValue(DownloadsAnchorKey.self) { anchors in
            // The button reports an anchor from this tree (top bars) or a frame from the sidebar's own host.
            GeometryReader { geometry in
                let toolbar = anchors.toolbar.map { geometry[$0] } ?? chrome.downloadsButtonFrame
                DownloadFeedbackOverlay(toolbar: toolbar, page: anchors.page.map { geometry[$0] },
                                        colors: state.tabLayout.usesTopTabs ? state.barPalette : state.palette, content: content)
                if chrome.showDownloads { DownloadsDropdownOverlay(state: state, chrome: chrome, anchor: toolbar, commands: commands) }
            }
        }
        .overlayPreferenceValue(AddressAnchorKey.self) { anchor in
            if state.tabLayout.usesTopTabs {
                GeometryReader { geometry in
                    AddressSuggestionsOverlay(anchor: anchor.map { geometry[$0] } ?? chrome.addressFieldFrame, state: state, chrome: chrome, palette: palette)
                }
            }
        }
        .onChange(of: state.activeTabID) { _, _ in chrome.showDownloads = false }
        .onChange(of: docksSidebar) { _, docked in
            guard !docked else { return sidebarMounted = true }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                if !docksSidebar { sidebarMounted = false }
            }
        }
        .onChange(of: state.tabLayout) { _, _ in chrome.showTabOverview = false; chrome.showDownloads = false }
        .animation(reduceMotion ? nil : .ikagoQuick, value: chrome.showDownloads)
        // The floating address bar and the sidebar's suggestions ease in and out; typing is never delayed by it.
        .animation(reduceMotion ? nil : .ikago, value: chrome.showPalette)
        .animation(reduceMotion ? nil : .ikago, value: showsSidebarSuggestions)
        .animation(.ikago, value: chrome.showTabOverview)
        .animation(.ikago, value: state.sidebarVisible)
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.36, dampingFraction: 0.9), value: state.showsSidebarRail)
        .animation(.ikago, value: state.tabLayout)
        .animation(revealAnimation, value: chrome.peeking)
        .animation(reduceMotion ? nil : .smooth(duration: 0.38), value: state.isImmersive)
        // Typing an address, or ⌘L / a new tab, brings the hidden bar in for as long as it lasts.
        .onChange(of: chrome.inlineAddress) { _, editing in
            guard state.isImmersive, state.tabLayout.usesTopTabs || !state.sidebarVisible else { return }
            if editing { chrome.peek() } else { chrome.endPeek(after: .milliseconds(600)) }
        }
        .onChange(of: chrome.showDownloads) { _, shown in
            if state.isImmersive, !shown { chrome.endPeek() }
        }
        // The bar tint animates inside the island (`IslandBarView`), so this body doesn't depend on the active tab's
        // URL and theme colour. Gap and rounding follow Settings sliders immediately instead of animating the window.
        .animation(.ikago, value: state.tabLayout == .horizontal && state.topBarShowsTabStrip)
        .environment(\.colorScheme, colors.isDark ? .dark : .light)
        .glassButtons(colors.glass)
        .tint(colors.accent)
        .sheet(item: Binding(get: { chrome.bookmarkToEdit }, set: { chrome.bookmarkToEdit = $0 })) { bookmark in
            BookmarkEditor(state: state, bookmark: bookmark)
        }
    }

    /// The top bars in their own host (`IsolatedHost`), at the height they set for themselves.
    private var topBar: some View {
        IsolatedHost(chrome: chrome) {
            TopBarBrowserView(state: state, chrome: chrome, palette: palette, commands: commands)
        }
        .frame(height: state.topBarHeaderHeight)
    }

    /// Full screen has no margins: the page meets the screen's edges.
    private var inset: CGFloat { state.isImmersive ? 0 : state.frameInset }
    /// The sidebar sits beside the page in its Full or Icons form, in full screen too; Hidden slides in over it.
    private var docksSidebar: Bool { state.sidebarVisible }
    /// Revealed chrome arrives with a soft spring and leaves a little quicker.
    private var revealAnimation: Animation? {
        reduceMotion ? .easeInOut(duration: 0.15) : chrome.peeking ? .spring(response: 0.34, dampingFraction: 0.86) : .smooth(duration: 0.24)
    }
    private var sidebarShownWidth: CGFloat { state.showsSidebarRail ? BrowserState.sidebarRailWidth : state.sidebarWidth }
    /// Width the sidebar takes before the page starts (0 without a visible sidebar).
    private var pageLeadingOffset: CGFloat {
        state.tabLayout == .vertical && docksSidebar ? sidebarShownWidth + inset + CGFloat(state.sidebarGap) : 0
    }
    /// Corners follow the border: flush panels are square.
    private var radius: CGFloat { inset == 0 ? 0 : 12 }

    private func contentCard(for layout: TabLayout) -> some View {
        ContentHost(view: content, state: state, layout: layout)
            .anchorPreference(key: DownloadsAnchorKey.self, value: .bounds) { DownloadAnchors(page: $0) }
            .recordLayout("content")
            .overlay { SplitDropOverlay(state: state, chrome: chrome) }
            .padding(.top, state.tabLayout == .vertical || state.isImmersive ? inset : state.barPageGap)
            .padding([.trailing, .bottom], inset)
            // The window's margins around the page move the window in every layout (the page itself is on top).
            .background(WindowDragArea())
            .overlay(alignment: .top) {
                if state.tabLayout == .vertical && inset > 1 {
                    WindowDragArea().frame(height: inset).padding(.trailing, inset)
                        .recordLayout("sidebar-page-drag-margin")
                }
            }
    }

    private var showsSidebarSuggestions: Bool {
        state.tabLayout == .vertical && chrome.isEditingAddress(of: state.activeTabID)
            && (!palette.suggestions.isEmpty || palette.error != nil)
    }

    @ViewBuilder private var overlays: some View {
        if chrome.showPalette {
            Color.black.opacity(state.isDark ? 0.25 : 0.08)
                .ignoresSafeArea()
                .onTapGesture { palette.onDismiss() }
                .transition(.opacity)
            CommandPaletteView(model: palette, colors: state.palette, commands: commands)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, state.tabLayout.usesTopTabs ? max(110, state.topBarChromeHeight + 12) : 110)
                .padding(.leading, pageLeadingOffset)  // centred on the page, not the window
                .transition(.scale(scale: 0.96, anchor: .top).combined(with: .opacity))
        }
        if showsSidebarSuggestions {
            // Under the sidebar's address field.
            SuggestionList(model: palette, colors: state.palette)
                .frame(width: 520)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 92)
                .padding(.leading, state.frameInset + 10)
                .transition(.scale(scale: 0.98, anchor: .topLeading).combined(with: .opacity))
        }
        if chrome.showFind {
            FindBarView(model: find, colors: state.palette)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, state.tabLayout.usesTopTabs && !state.isImmersive ? state.topBarChromeHeight + 8 : 20)
                .padding(.trailing, 20)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
