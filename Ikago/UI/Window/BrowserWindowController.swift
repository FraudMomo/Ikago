import AppKit
import SwiftUI
import WebKit

/// The main browser window: a tinted translucent backdrop with the SwiftUI shell on top
/// (sidebar or island bar, the content card, overlays). Owns commands, permission sheets
/// and the traffic lights.
@MainActor
final class BrowserWindowController: NSWindowController, NSWindowDelegate {
    let state: BrowserState
    let chrome = ChromeModel()
    let palette: CommandPaletteModel
    let find = FindBarModel()
    let content: WebContentViewController
    let background = WindowBackgroundView()
    private var permissionQueue: [(tab: TabController, request: PermissionRequest)] = []
    private var permissionSheet: NSWindow?
    private var pageWindowGrab: PageWindowGrab?
    private var appearanceObservation: NSKeyValueObservation?
    /// Ikago's own traffic lights while the window is full screen.
    lazy var fullScreenControls = FullScreenWindowControls(window: window!)
    /// Ikago's full screen: the windowed frame and autosave name to go back to, and the band above the bars.
    var fullScreenRestore: (frame: NSRect, autosave: String)?
    let fullScreenBand = NSView()
    /// The menu bar's height on the full-screen display.
    var fullScreenMenuBar: CGFloat = 0

    var activeController: TabController? { content.activeController }

    init(state: BrowserState) {
        self.state = state
        palette = CommandPaletteModel(state: state)
        content = WebContentViewController(state: state)
        let window = BrowserWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1320, height: 860),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        // Only `WindowDragArea` moves the window: tabs and the island must never start a window drag.
        window.isMovable = false
        window.titlebarSeparatorStyle = .none
        window.minSize = NSSize(width: 420, height: 320)
        if !WebProfiles.isTestMode, !state.isPrivate, CEFSessions.overrideRoot == nil {
            window.setFrameAutosaveName("IkagoMainWindow")
        }
        if state.isPrivate { window.title = "Private" }  // Window menu and Mission Control
        // An empty toolbar makes the titlebar tall enough to centre the traffic lights on
        // the sidebar's top row and the island bar.
        let toolbar = NSToolbar(identifier: "Ikago")
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        super.init(window: window)
        window.protectsAddressFocus = { [weak self] in self?.isEditingAddress == true && self?.state.isFrozen == false }

        window.dismissAddress = { [weak self] in self?.dismissCommandPalette() }

        content.host = self
        content.shouldFocusPage = { [weak self] in self?.isEditingAddress != true }
        background.frame = NSRect(origin: .zero, size: window.contentLayoutRect.size)
        window.contentView = background
        let root = NSHostingView(rootView: BrowserRootView(state: state, chrome: chrome, palette: palette, find: find,
                                                           content: content.view, commands: self).environment(\.privateBrowsing, state.isPrivate))
        root.sizingOptions = []  // content must follow the window, not impose its fitting width
        root.safeAreaRegions = []  // the shell draws under the titlebar itself
        root.frame = background.bounds
        root.autoresizingMask = []
        background.shell = root
        background.addSubview(root)
        window.delegate = self
        window.fullScreenHandler = { [weak self] in self?.toggleIkagoFullScreen() }
        if window.frame.origin == .zero { window.center() }
        restorePerformanceStats()

        configureOverlays()
        content.start()
        pageWindowGrab = PageWindowGrab(content: content.view, state: state)
        if !state.isPrivate { ExtensionManager.shared.browser = self }
        ExtensionManager.shared.windowOpened(self)
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.initial, .new]) { [weak self] app, _ in
            MainActor.assumeIsolated {
                self?.state.systemIsDark = app.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            }
        }
        // Switching tabs ends address editing (the field would show the old tab's address).
        observeState { [weak self] in _ = self?.state.activeTabID } onChange: { [weak self] in
            guard let self, self.isEditingAddress, self.state.activeTabID != self.chrome.editingTabID else { return }
            self.dismissCommandPalette()
        }
        observeState { [weak self] in
            guard let self else { return }
            _ = (state.palette.nsTint, state.isDark, state.tabLayout, state.sidebarVisible, chrome.peeking, state.isImmersive, state.developerTools, state.browserPreferences.translucentSidebar,
                 state.browserPreferences.sidebarCompact, state.browserPreferences.fullScreenUnderNotch, state.frameInset)
        } onChange: { [weak self] in self?.applyChrome() }
        // Bar size changes (a slider drag fires many) only move the traffic lights; everything
        // else in applyChrome is far heavier.
        observeState {
            _ = (state.barHeight, state.barGap, state.barRounded, state.barShownHeight)
        } onChange: { [weak self] in
            self?.positionTrafficLights()
        }
        applyChrome()
        // AppKit puts the traffic lights back on resize and full screen; move them again after it has.
        for name in [NSWindow.didResizeNotification, NSWindow.didExitFullScreenNotification, NSWindow.didEndLiveResizeNotification] {
            NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { DispatchQueue.main.async { self?.positionTrafficLights() } }
            }
        }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    /// Backdrop color, window appearance and traffic-light visibility.
    private func applyChrome() {
        guard let window else { return }
        let colors = state.palette
        background.apply(colors, translucentSidebar: state.tabLayout == .vertical && state.browserPreferences.translucentSidebar == true)
        if WebProfiles.developerTools != state.developerTools {
            WebProfiles.developerTools = state.developerTools
            for controller in content.controllers.values { controller.page?.setDeveloperTools(state.developerTools) }
        }
        let appearance = NSAppearance(named: colors.isDark ? .darkAqua : .aqua)
        if window.appearance != appearance { window.appearance = appearance }
        if let window = browserWindow, window.isIkagoFullScreen {
            window.fullScreenTopBand = fullScreenBandHeight(on: window.screen)
            layoutFullScreenBand()
        }
        positionTrafficLights()
        let showLights = showsTrafficLights
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            for kind: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(kind)?.animator().alphaValue = showLights ? 1 : 0
            }
        }
    }

    // MARK: Overlays

    private func configureOverlays() {
        palette.onOpen = { [weak self] url, mode in
            self?.dismissCommandPalette()
            self?.open(url, inNewTab: mode == .newTab || self?.state.activeTab == nil)
            // Counts as a typed visit for omnibox ranking (Chromium's typed_count).
            if let self, let id = self.state.activeTabID { self.state.typedNavigations.insert(id) }
        }
        palette.onSwitch = { [weak self] id in
            self?.dismissCommandPalette()
            withAnimation(.ikago) { self?.state.select(id) }
        }
        palette.onDismiss = { [weak self] in self?.dismissCommandPalette() }
        find.onSearch = { [weak self] text, forward, _ in
            self?.activeController?.page?.find(text, forward: forward, matchCase: false)
        }
        find.onClose = { [weak self] in self?.closeFindBar() }
    }

    func showFindBar() {
        guard state.activeTab != nil else { return }
        withAnimation(.ikago) { chrome.showFind = true }
        find.search()
    }

    func closeFindBar() {
        activeController?.page?.clearFindSelection()
        find.matchCount = 0
        withAnimation(.ikagoQuick) { chrome.showFind = false }
        activeController?.focus()
    }

    // MARK: Navigation

    func open(_ url: String, inNewTab: Bool) {
        if let page = InternalPage(url: url) { return openPage(page) }
        if inNewTab || state.activeTab == nil || state.addressNeedsNewTab(for: url) {
            withAnimation(.ikago) { _ = state.newTab(url: url) }
        } else if let controller = activeController {
            controller.load(url)
        }
    }

    /// Settings, History, Downloads: one tab per Space, reused when already open.
    func openPage(_ page: InternalPage) {
        chrome.showDownloads = false
        chrome.showTabOverview = false
        withAnimation(.ikago) {
            if let existing = state.spaceTabs.first(where: { $0.url == page.url }) {
                state.select(existing.id)
            } else {
                state.newTab(url: page.url)
            }
        }
        window?.makeKeyAndOrderFront(nil)
    }

    func showSettings() { openPage(.settings) }

    // MARK: Permissions (one sheet at a time, fail-closed)

    private func presentNextPermission() {
        guard permissionSheet == nil, let window, let next = permissionQueue.first else { return }
        let sheet = NSWindow(contentViewController: NSHostingController(rootView:
            PermissionPromptSheet(request: next.request) { [weak self] decision in
                self?.finishPermission(decision)
            }))
        permissionSheet = sheet
        state.select(next.tab.tab.id)
        window.beginSheet(sheet)
    }

    func finishPermission(_ decision: PermissionRequest.Decision) {
        guard !permissionQueue.isEmpty else { return }
        let entry = permissionQueue.removeFirst()
        entry.request.resolve(decision)
        if let sheet = permissionSheet { window?.endSheet(sheet) }
        permissionSheet = nil
        presentNextPermission()
    }

    /// Drops (and thereby denies) queued requests for a tab that is going away.
    func discardPermissions(for tab: TabController) {
        let presentingThisTab = permissionQueue.first?.tab === tab
        permissionQueue.filter { $0.tab === tab }.forEach { $0.request.resolve(.deny) }
        permissionQueue.removeAll { $0.tab === tab }
        if presentingThisTab, let sheet = permissionSheet {
            window?.endSheet(sheet)
            permissionSheet = nil
            presentNextPermission()
        }
    }

    // MARK: NSWindowDelegate

    func windowDidBecomeKey(_ notification: Notification) {
        applyFullScreenPresentation()
        positionTrafficLights()
        ExtensionManager.shared.windowFocused(self)
    }

    func windowDidResignKey(_ notification: Notification) {
        applyFullScreenPresentation()
    }

    func windowWillClose(_ notification: Notification) {
        if browserWindow?.isIkagoFullScreen == true {
            browserWindow?.isIkagoFullScreen = false
            applyFullScreenPresentation()
        }
        permissionQueue.forEach { $0.request.resolve(.deny) }
        permissionQueue.removeAll()
        state.freezeForShutdown()
        content.shutdown()
        pageWindowGrab?.stop()
        if state.isPrivate {
            WebProfiles.forget(state.privateProfileID)
            (NSApp.delegate as? AppDelegate)?.privateWindowClosed(self)
        }
    }
}

// MARK: - TabHost

extension BrowserWindowController: TabHost {
    func tabController(_ tab: TabController, adoptCEFPopup page: CEFWebTab, url: String, background: Bool) -> Bool {
        content.adoptCEFPopup(page, url: url, background: background, opener: tab)
    }
    /// WebKit already blocked popups without a user gesture; the rest become tabs.
    func tabController(_ tab: TabController, popupWith configuration: WKWebViewConfiguration,
                       url: String, background: Bool) -> WKWebView? {
        content.adoptPopup(configuration: configuration, url: url, background: background, opener: tab)
    }

    func tabController(_ tab: TabController, openInNewTab url: String, background: Bool) {
        state.newTabFromLink(url: url, opener: tab.tab, select: !background)
    }

    func tabController(_ tab: TabController, requestsPermission request: PermissionRequest) {
        request.onInvalidated = { [weak self, weak tab] in
            if let tab { self?.discardPermissions(for: tab) }
        }
        permissionQueue.append((tab, request))
        presentNextPermission()
    }

    func tabController(_ tab: TabController, didFind found: Bool) {
        guard tab === activeController else { return }
        find.matchCount = found ? 1 : 0
        find.activeMatch = found ? 1 : 0
    }

    func tabControllerEndedDrag(_ tab: TabController) { chrome.endTabDrag() }
    func tabControllerBeganDrag(_ tab: TabController) { chrome.beginTabDrag(tab.tab.id) }

    func tabControllerDidClose(_ tab: TabController) {
        discardPermissions(for: tab)
    }
}
