import AppKit
import IKCEFBridge
import SwiftUI
import WebKit
/// The main browser window: a tinted translucent backdrop with the SwiftUI shell on top
/// (the sidebar, the content card, overlays). Owns commands, the permission prompt queue
/// and the traffic lights.
@MainActor
final class BrowserWindowController: NSWindowController, NSWindowDelegate {
    var peekController: TabController?
    var peekIsTemporary = false
    let state: BrowserState
    let chrome = ChromeModel()
    /// Observers for native popovers over this window (see `init`); removed when the controller goes away.
    private var popoverObservers: [NSObjectProtocol] = []
    let palette: CommandPaletteModel
    let find = FindBarModel()
    /// Find belongs to each tab: its own search text, and whether its find bar is open. A tab never
    /// starts from another tab's search, and switching tabs shows or hides the bar with the tab.
    var findTexts: [String: String] = [:]
    var findOpenTabs: Set<String> = []
    /// The tab whose search the find bar holds now.
    private var findTabID: String?
    let content: WebContentViewController
    let background = WindowBackgroundView()
    /// Permission requests waiting for the prompt, one entry per tab and site: a site asking again (or for another
    /// device) while it waits joins its entry, so it is asked once.
    private var permissionQueue: [PendingPermission] = []
    private(set) var pageWindowGrab: PageWindowGrab?
    /// The icon sidebar's hover effects, drawn in a window over this one (`RailOverlay`).
    private var railOverlay: RailOverlay?
    private var systemAppearance: SystemAppearance?
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
        // Only `WindowDragArea` moves the window: tabs must never start a window drag.
        window.isMovable = false
        window.titlebarSeparatorStyle = .none
        window.minSize = NSSize(width: 420, height: 320)
        if !WebProfiles.isTestMode, !state.isPrivate, CEFSessions.overrideRoot == nil {
            window.setFrameAutosaveName("IkagoMainWindow")
        }
        if state.isPrivate { window.title = "Private" }  // Window menu and Mission Control
        // An empty toolbar makes the titlebar tall enough to centre the traffic lights on
        // the sidebar's top row.
        let toolbar = NSToolbar(identifier: "Ikago")
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        super.init(window: window)
        window.protectsAddressFocus = { [weak self] in self?.isEditingAddress == true && self?.state.isFrozen == false }
        window.typeAhead = { [weak self] characters in
            guard let self else { return false }
            // An untouched field's text (the page address on ⌘L) is replaced, as typing over a selection would.
            self.palette.userEdited((self.palette.edited ? self.palette.query : "") + characters)
            return true
        }
        window.dismissAddress = { [weak self] in self?.dismissCommandPalette() }
        content.host = self
        // An extension's popup is a native popover over this window; while one is open the tabs beneath it stay quiet.
        var shownPopovers = Set<ObjectIdentifier>()
        for name in [NSPopover.willShowNotification, NSPopover.didCloseNotification] {
            popoverObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let popover = (note.object as? NSPopover).map(ObjectIdentifier.init)
                MainActor.assumeIsolated {
                    guard let self, let popover else { return }
                    if name == NSPopover.willShowNotification {
                        guard self.window?.isKeyWindow == true else { return }
                        shownPopovers.insert(popover)
                    } else { shownPopovers.remove(popover) }
                    self.chrome.nativePopovers = shownPopovers.count
                }
            })
        }
        chrome.onTabDragEnded = { [weak self] id, point in self?.tabDraggedOut(id, at: point) }
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
        let overlay = RailOverlay(parent: window, content: RailHoverLayers(state: state, chrome: chrome, palette: palette, commands: self)
            .environment(\.privateBrowsing, state.isPrivate))
        railOverlay = overlay
        chrome.rail.onOverlay = { [weak overlay, weak rail = chrome.rail] shown in
            overlay?.show(shown)
            rail?.overlayOnScreen = shown && overlay?.isShown == true
        }
        chrome.rail.onPrepare = { [weak overlay] in overlay?.prepare() }
        // Expand opens the full sidebar at the width the person gave it.
        chrome.rail.expandWidth = { [weak state] in CGFloat(state?.sidebarWidth ?? Double(RailHover.expandedWidth)) }
        chrome.rail.onPassThrough = { [weak overlay] through in overlay?.passThrough(through) }
        // The rail's traffic lights stay uncovered by the wider rail.
        chrome.rail.lightsRect = { [weak self] in
            guard let self, let window = self.window else { return nil }
            let rects = self.fullScreenControls.lightRects(in: window)
            return rects.isEmpty ? nil : rects.dropFirst().reduce(rects[0]) { $0.union($1) }
        }
        chrome.rail.lightFrames = { [weak self] in
            guard let self, let window = self.window else { return [] }
            return self.fullScreenControls.lightRects(in: window)
        }
        if !state.isPrivate {
            ExtensionManager.shared.browser = self
            // Spaces, settings, history and bookmarks are shared by every regular window (`BrowserState+Windows`).
            observeState { [weak self] in self?.state.readShared() } onChange: { [weak self] in self?.state.shareChanges() }
        }
        ExtensionManager.shared.windowOpened(self)
        systemAppearance = SystemAppearance { [weak self] dark in
            if self?.state.systemIsDark != dark { self?.state.systemIsDark = dark }
        }
        // Switching tabs ends address editing (the field would show the old tab's address).
        observeState { [weak self] in _ = self?.state.activeTabID } onChange: { [weak self] in
            guard let self else { return }
            self.activeTabChangedForFind()
            guard self.isEditingAddress, self.state.activeTabID != self.chrome.editingTabID else { return }
            self.dismissCommandPalette()
        }
        observeState { [weak self] in
            guard let self else { return }
            _ = (state.palette.nsTint, state.isDark, state.sidebarVisible, chrome.peeking, state.isImmersive, state.developerTools, state.browserPreferences.translucentSidebar,
                 state.browserPreferences.sidebarOnRight, state.browserPreferences.sidebarLightsFollow, state.browserPreferences.sidebarCompact, state.browserPreferences.fullScreenUnderNotch, state.frameInset,
                 state.browserPreferences.sidebarTopTabs, state.browserPreferences.addressAbovePage, state.useGlass, state.colorMode)
        } onChange: { [weak self] in self?.applyChrome() }
        // Sidebar width changes (a drag fires many) only move the traffic lights; everything
        // else in applyChrome is far heavier.
        let rail = chrome.rail
        observeState {
            _ = (state.sidebarWidth, rail.expanded)
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
        background.apply(colors, translucentSidebar: state.browserPreferences.translucentSidebar == true)
        if WebProfiles.developerTools != state.developerTools {
            WebProfiles.developerTools = state.developerTools
            for controller in content.controllers.values { controller.page?.setDeveloperTools(state.developerTools) }
        }
        let appearance = NSAppearance(named: colors.isDark ? .darkAqua : .aqua)
        if window.appearance != appearance { window.appearance = appearance }
        // Light or dark changed: open pages pick their icon for the new mode once (sites may offer one per mode).
        // Chromium pages follow Ikago's mode, not macOS's (WebKit pages follow the window's appearance already).
        // App-wide, so regular windows decide: a private window (always dark) must not darken every window's pages.
        if !state.isPrivate { ChromiumAppearance.apply(dark: state.colorMode == .system ? nil : state.colorMode == .dark) }
        if FaviconCache.shared.dark != colors.isDark {
            FaviconCache.shared.dark = colors.isDark
            for controller in content.controllers.values { controller.page?.refreshFavicon() }
        }
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
        palette.onAction = { [weak self] action in action.perform(in: self?.window) }
        find.onSearch = { [weak self] text, forward, next in
            guard let self, let controller = self.activeController, let page = controller.page else { return }
            guard !text.isEmpty else {
                page.clearFindSelection()
                controller.showFindTicks([], active: nil)
                return
            }
            // The count and the selected match arrive with the result (`tabController(_:didFind:)`).
            // A new search (typing, not Next/Previous) may come back from Chromium with every match marked and none
            // selected; it then gets one step, so it reads "1 of N" at once.
            self.find.selectsFirstMatch = !next && page is CEFWebTab
            page.find(text, forward: forward, matchCase: self.find.matchCase)
        }
        find.onHighlightAllChanged = { [weak self] in
            guard let self, let controller = self.activeController else { return }
            self.refreshFindDetails(controller)
        }
        find.onClose = { [weak self] in self?.closeFindBar() }
    }
    func showFindBar() {
        guard let id = state.activeTabID else { return }
        // Each tab remembers its last search; a tab without one starts from the Mac's shared find text (⌘E).
        if !chrome.showFind {
            let remembered = findTexts[id] ?? ""
            if find.text != remembered { find.text = remembered }
        }
        findTabID = id
        findOpenTabs.insert(id)
        // Chromium marks every match itself, so the toggle is only for WebKit.
        find.offersHighlightAll = !(activeController?.page is CEFWebTab)
        withAnimation(.ikago) { chrome.showFind = true }
        find.search()
        focusFindField()
    }
    /// Gives the keyboard to the find field with its text selected, also when the bar is already open. The page (a
    /// web view or a Chromium page) usually holds the keyboard, and SwiftUI's focus alone didn't take it from there.
    private func focusFindField() {
        let focus: @MainActor () -> Void = { [weak self] in
            guard let self, self.chrome.showFind, let window = self.window, let root = window.contentView else { return }
            @MainActor func field(in view: NSView) -> NSTextField? {
                if let field = view as? NSTextField, field.isEditable, field.placeholderString == "Find in page",
                   !field.isHiddenOrHasHiddenAncestor { return field }
                return view.subviews.lazy.compactMap(field(in:)).first
            }
            guard let field = field(in: root) else { return }
            if let editor = field.currentEditor(), window.firstResponder === editor { return }
            window.makeFirstResponder(field)
            field.currentEditor()?.selectAll(nil)
        }
        DispatchQueue.main.async { focus() }
        // Again once the bar's appearance has settled (it is inserted with an animation).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { focus() }
    }
    /// WebKit's find says only whether it found one: count the matches, find which one it selected, mark them all
    /// (Highlight All) and place the tick marks. Chromium reports the count itself and draws its own ticks.
    func refreshFindDetails(_ controller: TabController) {
        guard let page = controller.page, !(page is CEFWebTab) else { return }
        let text = find.text, matchCase = find.matchCase
        guard !text.isEmpty else {
            Task { _ = try? await page.evaluate(FindHighlights.clearScript) }
            controller.showFindTicks([], active: nil)
            return
        }
        Task { [weak self, weak controller] in
            let details = (try? await page.callAsync(FindHighlights.detailsBody(text, matchCase: matchCase, mark: self?.find.highlightAll ?? false))) as? [String: Any]
            guard let self, let controller, let details, self.find.text == text, self.chrome.showFind, controller === self.activeController else { return }
            let total = (details["total"] as? NSNumber)?.intValue ?? 0
            self.find.totalMatches = total
            self.find.activeMatch = (details["active"] as? NSNumber)?.intValue ?? 0
            self.find.matchCount = total
            let activeTick = (details["activeTick"] as? NSNumber)?.doubleValue ?? -1
            controller.showFindTicks((details["ticks"] as? [NSNumber])?.map(\.doubleValue) ?? [], active: activeTick >= 0 ? activeTick : nil)
        }
    }

    /// Switching tabs: the tab left behind keeps its search (its marks go), and the newly selected tab brings back its
    /// own find bar if it had one open, with its own text; otherwise the bar hides.
    private func activeTabChangedForFind() {
        for controller in content.controllers.values where controller !== activeController { controller.showFindTicks([], active: nil) }
        let id = state.activeTabID
        if let previous = findTabID, previous != id {
            findTexts[previous] = find.text.isEmpty ? nil : find.text
            content.controllers[previous]?.page?.clearFindSelection()
            findTabID = nil
        }
        findOpenTabs = findOpenTabs.filter { state.tab($0) != nil }
        findTexts = findTexts.filter { state.tab($0.key) != nil }
        find.matchCount = 0; find.activeMatch = 0; find.totalMatches = nil
        guard let id, findOpenTabs.contains(id) else {
            if chrome.showFind { withAnimation(.ikagoQuick) { chrome.showFind = false } }
            return
        }
        findTabID = id
        find.offersHighlightAll = !(activeController?.page is CEFWebTab)
        let text = findTexts[id] ?? ""
        if chrome.showFind && find.text != text {
            find.text = text  // the open field searches as its text changes
        } else {
            if find.text != text { find.text = text }
            if !chrome.showFind { withAnimation(.ikagoQuick) { chrome.showFind = true } }
            find.search()
        }
    }
    /// After the access card allowed something: reload the tab that asked (in split view, its own pane).
    func reloadForExtensionAccess(_ offer: ExtensionAccessOffer) {
        let controller = offer.tabID.flatMap { id in content.controllers[id] } ?? activeController
        controller?.page?.reload()
    }
    func closeFindBar() {
        if let id = state.activeTabID {
            findTexts[id] = find.text.isEmpty ? nil : find.text
            findOpenTabs.remove(id)
        }
        findTabID = nil
        activeController?.page?.clearFindSelection()
        activeController?.showFindTicks([], active: nil)
        find.matchCount = 0
        find.activeMatch = 0
        find.totalMatches = nil
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
        } else if let tab = state.activeTab {
            // Its page isn't made yet (⌘T then Return straight away): it starts at this address when it is. Dropping
            // the address here left an empty tab, as if the new tab had vanished.
            tab.url = url
            state.scheduleSave()
        }
    }

    /// Settings, History, Downloads: one tab per Space, reused when already open.
    func openPage(_ page: InternalPage) {
        if page == .notes { chrome.showNotes.toggle(); return }
        chrome.showDownloads = false
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

    // MARK: Permissions (one prompt at a time, fail-closed)

    private func presentNextPermission() {
        guard chrome.permissionPrompt == nil, let next = permissionQueue.first else { return }
        state.select(next.tab.tab.id)
        withAnimation(.ikago) {
            chrome.permissionPrompt = PermissionPromptItem(origin: next.origin, kinds: next.kinds, tabID: next.tab.tab.id,
                                                           isPrivate: state.isPrivate)
        }
    }

    /// The prompt's answer: recorded for the site (or this visit), then every request it covered is resolved.
    func finishPermission(_ choice: PermissionChoice) {
        guard !permissionQueue.isEmpty else { return }
        let entry = permissionQueue.removeFirst()
        state.applyPermission(choice, kinds: entry.kinds, origin: entry.origin, tabID: entry.tab.tab.id)
        let decision: PermissionRequest.Decision
        if case .allow = choice { decision = .allow } else { decision = .deny }
        entry.requests.forEach { $0.resolve(decision) }
        withAnimation(.ikagoQuick) { chrome.permissionPrompt = nil }
        // A queued request the answer now covers (the same site in another tab, allowed for good) needs no prompt.
        permissionQueue.removeAll { pending in
            guard let remembered = state.rememberedDecision(origin: pending.origin, kinds: pending.kinds,
                                                            tabID: pending.tab.tab.id) else { return false }
            pending.requests.forEach { $0.resolve(remembered) }
            return true
        }
        presentNextPermission()
    }

    /// Drops (and thereby denies) queued requests for a tab that is going away.
    func discardPermissions(for tab: TabController) {
        let presentingThisTab = permissionQueue.first?.tab === tab && chrome.permissionPrompt != nil
        permissionQueue.filter { $0.tab === tab }.forEach { $0.requests.forEach { $0.resolve(.deny) } }
        permissionQueue.removeAll { $0.tab === tab }
        if presentingThisTab {
            chrome.permissionPrompt = nil
            presentNextPermission()
        }
    }

    // MARK: NSWindowDelegate

    /// Every page this window owns, the link preview's included: Chromium can't shut down while one is still open.
    func closeAllPages() {
        closePeek()
        content.shutdown()
    }

    func windowWillClose(_ notification: Notification) {
        chrome.textPrompt?.finish(nil)
        closePeek()
        if browserWindow?.isIkagoFullScreen == true {
            browserWindow?.isIkagoFullScreen = false
            applyFullScreenPresentation()
        }
        permissionQueue.forEach { $0.requests.forEach { $0.resolve(.deny) } }
        permissionQueue.removeAll()
        state.freezeForShutdown()
        content.shutdown()
        pageWindowGrab?.stop()
        if state.isPrivate {
            NotesPage.closePrivateNotes(state.privateProfileID)
            WebProfiles.forget(state.privateProfileID)
            (NSApp.delegate as? AppDelegate)?.privateWindowClosed(self)
        }
        BrowserWindows.closed(self)
    }
}

/// Requests from one tab and site waiting for one prompt.
private struct PendingPermission {
    let tab: TabController
    let origin: String
    var kinds: PermissionRequest.Kinds
    var requests: [PermissionRequest]
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

    /// A link the page asked to open in a new tab. Pages may only send people to web pages and extension pages:
    /// never Ikago's own pages, scripts or data documents, and local files only from a local file.
    func tabController(_ tab: TabController, openInNewTab url: String, background: Bool) {
        guard AddressResolver.isWebURL(url) || ExtensionURL.isExtension(url)
                || (AddressResolver.isLocalFileURL(url) && AddressResolver.isLocalFileURL(tab.tab.url)) else { return }
        if opensOutsideWebApp(url) { return }
        state.newTabFromLink(url: url, opener: tab.tab, select: !background)
    }

    func tabController(_ tab: TabController, requestsPermission request: PermissionRequest) {
        // The site card lists what a site has asked for, whatever the answer.
        state.noteRequested(request.kinds, origin: request.origin)
        if let remembered = state.rememberedDecision(origin: request.origin, kinds: request.kinds, tabID: tab.tab.id) {
            return request.resolve(remembered)
        }
        request.onInvalidated = { [weak self, weak tab] in
            if let tab { self?.discardPermissions(for: tab) }
        }
        // The same tab and site already waiting: one prompt answers both (sites often ask again, or for the camera and
        // then the microphone). The prompt on screen widens to what both asked for.
        if let index = permissionQueue.firstIndex(where: { $0.tab === tab && $0.origin == request.origin }) {
            permissionQueue[index].requests.append(request)
            permissionQueue[index].kinds.formUnion(request.kinds)
            if index == 0, chrome.permissionPrompt != nil { chrome.permissionPrompt?.kinds = permissionQueue[0].kinds }
            return
        }
        permissionQueue.append(PendingPermission(tab: tab, origin: request.origin, kinds: request.kinds, requests: [request]))
        presentNextPermission()
    }

    func tabController(_ tab: TabController, didFind result: FindResult) {
        guard tab === activeController, chrome.showFind else { return }
        if result.total != nil || result.active != nil {
            // Chromium: the count (final) and the selected match (often an earlier update) can come separately.
            if let total = result.total { find.matchCount = total; find.totalMatches = total }
            if let active = result.active { find.activeMatch = active; find.selectsFirstMatch = false }
            else if result.total == 0 { find.activeMatch = 0 }
            if find.selectsFirstMatch, (result.total ?? 0) > 0, result.active == nil, let page = tab.page {
                find.selectsFirstMatch = false
                page.find(find.text, forward: true, matchCase: find.matchCase)
            }
        } else {
            find.matchCount = result.found ? max(1, find.matchCount) : 0
            refreshFindDetails(tab)
        }
    }

    func tabControllerEndedDrag(_ tab: TabController) { chrome.endTabDrag() }
    func tabControllerBeganDrag(_ tab: TabController) { chrome.beginTabDrag(tab.tab.id) }

    func tabControllerDidClose(_ tab: TabController) {
        discardPermissions(for: tab)
    }
}
