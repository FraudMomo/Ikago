import AppKit
import SwiftUI

/// The whole window below the titlebar: the sidebar, the web content card, and the
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
    @Environment(\.appearsActive) private var appearsActive
    /// The docked sidebar stays mounted while it slides out, then leaves the tree.
    @State private var sidebarMounted = true
    var sidebarMountedForPlacement: Bool { sidebarMounted }

    var body: some View {
        let colors = state.palette
        ZStack(alignment: .topLeading) {
            if state.webApp != nil { webAppLayout } else { sidebarLayout }
            if !docksSidebar && state.webApp == nil {
                SidebarPeek(state: state, chrome: chrome, palette: palette, commands: commands)
            }
            // The icon sidebar's hover effects draw over the rail and the page (`RailHover`).
            if state.webApp == nil && state.browserPreferences.railHover != nil {
                RailHoverLayers(state: state, chrome: chrome, palette: palette, commands: commands)
            }
            if state.webApp == nil, state.sidebarOnRight && !state.sidebarLightsFollow && !state.showsSidebarTopTabs && !state.isImmersive {
                Capsule().fill(.regularMaterial).frame(width: 86, height: 32).padding(.leading, 8).padding(.top, 7).allowsHitTesting(false)
            }
            overlays
            IntegratedEditors(state: state, chrome: chrome, commands: commands)
            if chrome.showNotes {
                Color.black.opacity(0.1).onTapGesture { chrome.showNotes = false }
                NotesPage(state: state).frame(maxWidth: 640, maxHeight: 540)
                    .modalSurface(state.palette)
                    .overlay(alignment: .topTrailing) { ModalCloseButton(colors: state.palette, action: { chrome.showNotes = false }).padding(18) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity).transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .onExitCommand { chrome.showNotes = false }
            }
            if chrome.showSiteInfo { SiteInfoOverlay(state: state, chrome: chrome, commands: commands) }
            if chrome.showClearData {
                Color.black.opacity(state.isDark ? 0.25 : 0.1).onTapGesture { chrome.showClearData = false }
                ClearDataSheet(state: state) { chrome.showClearData = false }
                    .frame(maxWidth: .infinity, maxHeight: .infinity).transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
            if let id = chrome.hoverTabID, let tab = state.tab(id) {
                GeometryReader { geometry in
                    let anchor = chrome.hoverTabAnchor
                    let width = TabPeek.width
                    // Beside the tab (rows in the sidebar), or under it (the Top Tabs row).
                    let below = state.showsSidebarTopTabs && geometry.size.height - anchor.maxY < SidebarTopTabs.height(state)
                    let x = below ? min(max(8, anchor.minX), geometry.size.width - width - 8)
                        : anchor.maxX + width + 12 < geometry.size.width ? anchor.maxX + 8 : max(8, anchor.minX - width - 8)
                    let y = below ? geometry.size.height - anchor.minY + 6
                        : max(8, min(geometry.size.height - TabPeek.maxHeight, geometry.size.height - anchor.maxY))
                    TabPeek(tab: tab, commands: commands, image: chrome.hoverImage)
                        .modalSurface(state.palette, radius: Radius.card)
                        .offset(x: x, y: y)
                        .id(id).transition(.opacity.combined(with: .scale(scale: 0.98)))
                }.allowsHitTesting(false)
            }
            if chrome.previewTabID != nil, let page = commands?.peekContent {
                Color.black.opacity(chrome.peekExpanding ? 0 : state.isDark ? 0.35 : 0.22)
                    .contentShape(Rectangle())
                    .onTapGesture { commands?.closePeek() }
                    .transition(.opacity)
                GeometryReader { geometry in
                    let rect = chrome.peekExpanding ? LivePeekPanel.frame(around: chrome.peekTarget)
                        : LivePeekPanel.frame(in: geometry.size)
                    LivePeekPanel(page: page, tab: commands?.peekTab, commands: commands, colors: state.palette,
                                  expanding: chrome.peekExpanding, finalPageSize: chrome.peekTarget.size)
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.92)).combined(with: .offset(y: 16)))
            }
            TranslationHost(chrome: chrome)
            // Cards that come and go at the top right, stacked: an update, save password, translation, extension access.
            VStack(alignment: .trailing, spacing: 10) {
                // The update card shows in the frontmost window only.
                if appearsActive, let phase = AppUpdates.shared.prompt.phase {
                    UpdateCard(prompt: AppUpdates.shared.prompt, phase: phase, colors: state.palette)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                if appearsActive, PasswordExportReminder.shared.showing, AppUpdates.shared.prompt.phase == nil {
                    PasswordExportReminderCard(reminder: .shared, state: state, commands: commands)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                if let offer = chrome.passwordSave {
                    PasswordSaveCard(offer: offer, colors: state.palette).id(offer.id)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                if let job = chrome.translationJob {
                    TranslationCard(job: job, colors: state.palette,
                                    remember: { (commands as? BrowserWindowController)?.rememberTranslationTarget($0) },
                                    showOriginal: { (commands as? BrowserWindowController)?.showOriginal() },
                                    close: { (commands as? BrowserWindowController)?.closeTranslation() })
                        .id(job.id)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                if let offer = chrome.extensionAccessOffer {
                    ExtensionAccessCard(offer: offer, colors: state.palette,
                                        reload: { (commands as? BrowserWindowController)?.reloadForExtensionAccess(offer) },
                                        close: { ExtensionAccessPresenter.shared.notNow(offer, in: chrome) })
                        .padding(.top, offer.paneInset.top).padding(.trailing, offer.paneInset.trailing)
                        .id(offer.id)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.top, 56).padding(.trailing, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            if let suggestions = chrome.passwordSuggestions {
                GeometryReader { geometry in
                    let frame = suggestions.frame(in: geometry.size)
                    PasswordSuggestionsView(suggestions: suggestions, colors: state.palette)
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                }
                .id(suggestions.id)
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            }
            if chrome.showPageAssistant && state.browserPreferences.pageIntelligence == true {
                PageAssistantView(state: state, chrome: chrome, commands: commands)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .onChange(of: state.browserPreferences.pageIntelligence) { _, enabled in if enabled != true { chrome.showPageAssistant = false } }
        .onChange(of: state.activeTabID) { _, _ in if !chrome.peekExpanding { commands?.closePeek() }; chrome.hoverTabID = nil; chrome.showClearData = false; chrome.showSiteInfo = false; chrome.translationJob = nil; chrome.extensionAccessOffer = nil; PasswordSuggestionsPresenter.shared.dismiss() }
        .onChange(of: chrome.inlineAddress) { _, editing in if editing { chrome.hoverTabID = nil } }
        .animation(reduceMotion ? nil : .ikago, value: chrome.showNotes)
        .animation(reduceMotion ? nil : .ikago, value: chrome.showClearData)
        .animation(reduceMotion ? nil : .ikagoQuick, value: chrome.showSiteInfo)
        .animation(reduceMotion ? nil : .ikago, value: chrome.textPrompt?.id)
        .animation(reduceMotion ? nil : .ikago, value: chrome.editFolderID)
        .animation(reduceMotion ? nil : .ikago, value: chrome.showNewSpace)
        .animation(reduceMotion ? nil : .ikago, value: chrome.showPageAssistant)
        .animation(reduceMotion ? nil : .ikagoQuick, value: chrome.passwordSuggestions?.id)
        .animation(reduceMotion ? nil : .ikago, value: chrome.passwordSave?.id)
        .environment(\.tabHighlightStyle, state.tabHighlightStyle)
        .environment(\.chromeModel, chrome)
        .recordLayout("shell")
        .overlayPreferenceValue(DownloadsAnchorKey.self) { anchors in
            // The sidebar's Downloads button reports its frame from the sidebar's own host.
            GeometryReader { geometry in
                let toolbar = anchors.toolbar.map { geometry[$0] } ?? chrome.downloadsButtonFrame
                DownloadFeedbackOverlay(toolbar: toolbar, page: anchors.page.map { geometry[$0] },
                                        colors: state.palette, content: content)
                if chrome.showDownloads { DownloadsDropdownOverlay(state: state, chrome: chrome, anchor: toolbar, commands: commands) }
                if chrome.showDevices { DevicesDropdownOverlay(state: state, chrome: chrome, anchor: anchors.devices.map { geometry[$0] }) }
            }
        }
        .onChange(of: state.activeTabID) { _, _ in chrome.showDownloads = false; chrome.showDevices = false }
        .onChange(of: docksSidebar) { _, docked in
            guard !docked else { return sidebarMounted = true }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                if !docksSidebar { sidebarMounted = false }
            }
        }
        .animation(reduceMotion ? nil : .ikagoQuick, value: chrome.showDownloads)
        .animation(reduceMotion ? nil : .ikagoQuick, value: chrome.showDevices)
        // The floating address bar and the sidebar's suggestions ease in and out; typing is never delayed by it.
        .animation(reduceMotion ? nil : .ikago, value: chrome.showPalette)
        .animation(reduceMotion ? nil : .ikago, value: showsSidebarSuggestions)
        .animation(.ikago, value: state.sidebarVisible)
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.36, dampingFraction: 0.9), value: state.showsSidebarRail)
        .animation(revealAnimation, value: chrome.peeking)
        .animation(nil, value: state.isImmersive)
        // Typing an address, or ⌘L / a new tab, brings the hidden bar in for as long as it lasts.
        .onChange(of: chrome.inlineAddress) { _, editing in
            guard state.isImmersive, !state.sidebarVisible else { return }
            if editing { chrome.peek() } else { chrome.endPeek(after: .milliseconds(600)) }
        }
        .onChange(of: chrome.showDownloads) { _, shown in
            if !shown { DownloadCenter.shared.dismissToolbarButton() }
            if state.isImmersive, !shown { chrome.endPeek() }
        }
        .environment(\.colorScheme, colors.isDark ? .dark : .light)
        .glassButtons(colors.glass)
        .tint(colors.accent)
        .sheet(item: Binding(get: { chrome.bookmarkToEdit }, set: { chrome.bookmarkToEdit = $0 })) { bookmark in
            BookmarkEditor(state: state, bookmark: bookmark)
        }
    }


    /// Full screen has no margins: the page meets the screen's edges.
    var inset: CGFloat { state.isImmersive ? 0 : state.frameInset }
    /// The sidebar sits beside the page in its Full or Icons form, in full screen too; Hidden slides in over it.
    var docksSidebar: Bool { state.sidebarVisible }
    /// Revealed chrome arrives with a soft spring and leaves a little quicker.
    private var revealAnimation: Animation? {
        reduceMotion ? .easeInOut(duration: 0.15) : chrome.peeking ? .spring(response: 0.34, dampingFraction: 0.86) : .smooth(duration: 0.24)
    }
    var sidebarShownWidth: CGFloat { state.showsSidebarRail ? BrowserState.sidebarRailWidth : state.sidebarWidth }
    /// Width the sidebar takes before the page starts (0 without a visible sidebar).
    private var pageLeadingOffset: CGFloat {
        docksSidebar && !state.sidebarOnRight ? sidebarShownWidth + inset + CGFloat(state.sidebarGap) : 0
    }
    /// Corners follow the border: flush panels are square.
    var radius: CGFloat { inset == 0 ? 0 : Radius.card }

    var contentCard: some View {
        ContentHost(view: content, state: state,
                    sideChrome: pageLeadingOffset + (state.sidebarOnRight && docksSidebar ? sidebarShownWidth + CGFloat(state.sidebarGap) : 0)
                        + ((chrome.showPageAssistant && state.browserPreferences.pageIntelligence == true) ? PageAssistantView.width : 0),
                    anchorTrailing: !state.sidebarOnRight)
            .anchorPreference(key: DownloadsAnchorKey.self, value: .bounds) { DownloadAnchors(page: $0) }
            .recordLayout("content")
            .overlay { SplitDropOverlay(state: state, chrome: chrome) }
            .padding(.trailing, (chrome.showPageAssistant && state.browserPreferences.pageIntelligence == true) ? PageAssistantView.width : 0)
            .padding(.top, state.sidebarOnRight && !state.sidebarLightsFollow && !state.showsSidebarTopTabs && !state.isImmersive ? 40 : 0)
            // Under the Sidebar layout's tab row the page meets the active tab directly.
            .padding(.top, state.showsSidebarTopTabs ? 0 : inset)
            .padding([.trailing, .bottom], inset)
            // The window's margins around the page move the window in every layout (the page itself is on top).
            .background(WindowDragArea())
            .overlay(alignment: .top) {
                if inset > 1 && !state.showsSidebarTopTabs {
                    WindowDragArea().frame(height: inset).padding(.trailing, inset)
                        .recordLayout("sidebar-page-drag-margin")
                }
            }
    }

    private var showsSidebarSuggestions: Bool {
        chrome.isEditingAddress(of: state.activeTabID)
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
                .padding(.top, 110)
                .padding(.leading, pageLeadingOffset)  // centred on the page, not the window
                .transition(.scale(scale: 0.96, anchor: .top).combined(with: .opacity))
        }
        if showsSidebarSuggestions, state.showsSidebarTopTabs, let field = chrome.addressFieldFrame {
            // Hanging from the address bar above the page, at least wide enough to read.
            let width = max(field.width, 460)
            SuggestionList(model: palette, colors: state.palette)
                .frame(width: width)
                .padding(.leading, max(8, field.midX - width / 2))
                .padding(.top, field.maxY + 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .transition(.scale(scale: 0.98, anchor: .top).combined(with: .opacity))
        } else if showsSidebarSuggestions {
            // Under the sidebar's address field.
            SuggestionList(model: palette, colors: state.palette)
                .frame(width: 520)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 92)
                .padding(.leading, state.sidebarOnRight ? 0 : state.frameInset + 10)
                .padding(.trailing, state.sidebarOnRight ? state.frameInset + 10 : 0)
                .frame(maxWidth: .infinity, alignment: state.sidebarOnRight ? .trailing : .leading)
                .transition(.scale(scale: 0.98, anchor: .topLeading).combined(with: .opacity))
        }
        if chrome.showFind {
            FindBarView(model: find, colors: state.palette)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, state.showsSidebarTopTabs ? SidebarTopTabs.height(state) + state.tabsToolbarHeight + 12 : 20)
                .padding(.trailing, 20)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
