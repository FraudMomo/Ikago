import AppKit
import SwiftUI
import WebKit

/// Observes `BrowserState` and reconciles it with live pages: one TabController per
/// tab, created lazily when first shown, torn down when the tab leaves the model.
@MainActor
final class WebContentViewController: NSViewController {
    let state: BrowserState
    weak var host: TabHost?
    private let surface = WebTabContainerView()
    /// The next tab switch shows its page at once: a Peek grown to the page's place becomes the tab (no fade).
    var switchesInstantly = false
    /// Where pages sit, in `view`'s coordinates.
    var pageArea: NSView { surface }
    private var emptyView: NSView!
    private(set) var controllers: [String: TabController] = [:]
    private var stopped = false
    private var lastActiveID: String?
    private var mouseMonitor: Any?
    private var historySwipe: HistorySwipe?
    private(set) lazy var memoryManagement = TabMemoryManagement(content: self)
    /// False while the user types in the address/command bar: don't hand the keyboard to the page.
    var shouldFocusPage: () -> Bool = { true }

    init(state: BrowserState) {
        self.state = state
        super.init(nibName: nil, bundle: nil)
        NotificationCenter.default.addObserver(forName: BrowserState.siteEnginesChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.followSiteEngines() }
        }
    }

    /// Site rules changed: tabs showing a site that now uses another engine move there. Visible ones reopen at once;
    /// background ones unload and start in the right engine when shown.
    private func followSiteEngines() {
        for controller in controllers.values {
            guard let page = controller.page, TabController.isWebsite(controller.tab.url),
                  controller.targetEngine(for: controller.tab.url) != page.engine else { continue }
            if controller.isActive { controller.load(controller.tab.url) } else { controller.hibernate() }
        }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let root = NSView()
        surface.frame = root.bounds
        surface.autoresizingMask = [.width, .height]
        root.addSubview(surface)
        let empty = FileDropHostingView(rootView: EmptyTabView(state: state, commands: { [weak self] in self?.host as? BrowserCommands }))
        empty.registerForDraggedTypes([.fileURL])
        empty.onFiles = { [weak self] in (self?.host as? BrowserCommands)?.openDroppedFiles($0) }
        empty.identifier = PageWindowGrab.pageSurface
        empty.frame = root.bounds
        empty.autoresizingMask = [.width, .height]
        WebTabContainerView.round(empty)
        root.addSubview(empty)
        emptyView = empty
        view = root
    }

    /// Begins mirroring the model (call once the window exists).
    func start() {
        _ = view
        // Preferences reach the protections on their own; only the few that matter reconfigure pages.
        BrowserSecurity.shared.apply(state.browserPreferences)
        observeState { [weak self] in _ = self?.state.browserPreferences } onChange: { [weak self] in
            guard let self, !self.stopped else { return }
            BrowserSecurity.shared.apply(self.state.browserPreferences)
        }
        observeState { [weak self] in self?.trackedState() } onChange: { [weak self] in self?.reconcile() }
        reconcile()
        memoryManagement.markVisible()
        // In split view, clicking into a pane focuses its tab (the address bar follows it).
        // Swipes Back/Forward across an engine handoff, which neither engine's own gesture can reach.
        historySwipe = HistorySwipe { [weak self] event in
            guard let self, event.window === self.view.window else { return nil }
            return self.state.visibleTabIDs.lazy.compactMap { self.controllers[$0] }.first { controller in
                controller.hostView.window != nil
                    && controller.hostView.bounds.contains(controller.hostView.convert(event.locationInWindow, from: nil))
            }
        }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.focusPane(at: event)
            return event
        }
    }

    private func focusPane(at event: NSEvent) {
        guard event.window === view.window, state.visibleTabIDs.count > 1 else { return }
        for id in state.visibleTabIDs where id != state.activeTabID {
            guard let host = controllers[id]?.hostView, host.window != nil else { continue }
            if host.bounds.contains(host.convert(event.locationInWindow, from: nil)) {
                if let header = controllers[id]?.header, !header.isHidden,
                   header.frame.contains(host.convert(event.locationInWindow, from: nil)) { return }
                state.select(id)
                return
            }
        }
    }

    var activeController: TabController? { state.activeTabID.flatMap { controllers[$0] } }

    func controller(for id: String) -> TabController? { controllers[id] }

    // MARK: Reconciliation

    /// Everything `reconcile()` depends on, read inside observation tracking.
    private func trackedState() {
        _ = state.tabs.map { ($0.id, $0.isHibernating) }
        // Layout, tab style and address style live in the preferences; security re-applies only when its own fields change.
        _ = state.browserPreferences
        _ = state.visibleTabIDs
        _ = state.splitLayout
        _ = state.isDark
        _ = state.activeTabID
        _ = state.palette.nsTint
        _ = state.frameInset
        _ = state.isImmersive
    }

    func shutdown() {
        guard !stopped else { return }
        stopped = true
        memoryManagement.stop()
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
        historySwipe?.stop(); historySwipe = nil
        for controller in controllers.values { controller.close() }
        controllers.removeAll()
    }
    private func reconcile() {
        guard !stopped else { return }
        let live = Set(state.tabs.map(\.id))
        for (id, controller) in controllers where !live.contains(id) || state.tab(id) !== controller.tab {
            controllers[id] = nil
            ExtensionManager.shared.tabClosed(controller)
            controller.close()
        }
        for tab in state.tabs where controllers[tab.id] == nil { ensureController(for: tab) }

        for controller in controllers.values where controller.tab.shouldStartInBackground {
            controller.tab.shouldStartInBackground = false
            if !controller.tab.isHibernating { controller.startIfNeeded() }
        }
        for controller in controllers.values where controller.tab.isHibernating && !controller.isActive { controller.hibernate() }
        let visible = state.visibleTabIDs.compactMap { id in controllers[id].map { (id: id, view: $0.hostView as NSView) } }
        emptyView.isHidden = !visible.isEmpty
        let fades = state.browserPreferences.instantTabSwitching != true && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        surface.show(visible, layout: state.splitLayout, animate: fades && !switchesInstantly)
        switchesInstantly = false
        surface.highlight(state.activeTabID, views: visible, color: state.palette.nsAccent)
        // Native video overlays stop monitoring while parked and resume when shown.
        for controller in controllers.values { controller.page?.visibilityChanged() }
        memoryManagement.markVisible()
        for id in state.visibleTabIDs { controllers[id]?.startIfNeeded() }
        for id in state.visibleTabIDs { controllers[id]?.refreshSplitHeader() }
        surface.setPaneBackground(state.isDark ? NSColor(hex: 0x1C1C1E) : .white)
        let switchedTab = state.activeTabID != lastActiveID
        let radius: CGFloat = state.pageCornerRadius
        // Under the Top Tabs address bar the page's top corners are square: the bar is the card's top.
        let squareTop = state.showsSidebarTopTabs
        if WebTabContainerView.cornerRadius != radius || WebTabContainerView.squareTop != squareTop {
            WebTabContainerView.cornerRadius = radius
            WebTabContainerView.squareTop = squareTop
            for controller in controllers.values { WebTabContainerView.round(controller.hostView) }
            WebTabContainerView.round(emptyView)
        }
        // Focus the page only when the tab actually changed, never mid-typing in the chrome.
        if switchedTab, shouldFocusPage() { activeController?.focus() }
        // Moving to a tab on the other engine (per-site engines) shows which engine it is, like a switch within a tab.
        if switchedTab, let active = activeController, let engine = active.tab.engine,
           let before = lastActiveID.flatMap({ controllers[$0]?.tab.engine }), before != engine {
            active.showEngineBadge(engine)
        }
        if let active = activeController, state.activeTabID != lastActiveID {
            ExtensionManager.shared.tabActivated(active, previous: lastActiveID.flatMap { controllers[$0] })
            lastActiveID = state.activeTabID
        }
    }

    /// The tab's controller, created (and announced to extensions) if it doesn't exist yet.
    @discardableResult
    func ensureController(for tab: TabItem) -> TabController? {
        if let existing = controllers[tab.id] { return existing }
        guard let host else { return nil }
        let controller = TabController(tab: tab, state: state, host: host)
        controllers[tab.id] = controller
        surface.park(controller.hostView)
        ExtensionManager.shared.tabOpened(controller)
        return controller
    }

    /// The tab is moving to another window: its controller leaves this window and hands over the live page, if any.
    func release(_ id: String) -> (page: WebTab?, popup: Bool)? {
        guard let controller = controllers.removeValue(forKey: id) else { return nil }
        ExtensionManager.shared.tabClosed(controller)
        return (controller.releasePage(), controller.isPopup)
    }

    /// A tab moved in from another window, keeping its live page.
    func adopt(_ tab: TabItem, page: WebTab?, popup: Bool) {
        guard let host, controllers[tab.id] == nil else { return }
        let controller = TabController(tab: tab, state: state, host: host, page: page, popup: popup)
        controllers[tab.id] = controller
        surface.park(controller.hostView)
        controller.hostView.frame = surface.bounds
        ExtensionManager.shared.tabOpened(controller)
    }

    /// A Peek kept as a tab: its live page moves straight from the preview into the tab's view, never out of the window.
    func adopt(_ tab: TabItem, fromPeek peek: TabController) {
        guard let host, controllers[tab.id] == nil else { return }
        let controller = TabController(tab: tab, state: state, host: host)
        controllers[tab.id] = controller
        surface.park(controller.hostView)
        controller.hostView.frame = surface.bounds
        if let page = peek.releasePage(inWindow: true) { controller.attach(page) }
        peek.hostView.removeFromSuperview()
        ExtensionManager.shared.tabOpened(controller)
    }

    func adoptCEFPopup(_ page: CEFWebTab, url: String, background: Bool, opener: TabController) -> Bool {
        guard let host, let tab = state.newTabFromLink(url: url.isEmpty ? "about:blank" : url, opener: opener.tab, select: !background) else { return false }
        let controller = TabController(tab: tab, state: state, host: host, page: page)
        controllers[tab.id] = controller
        surface.park(controller.hostView)
        // Sized like any page from the start: a Chromium page adopted at 0×0 could stay blank when shown.
        controller.hostView.frame = surface.bounds
        ExtensionManager.shared.tabOpened(controller)
        return true
    }
    /// Adopts a popup into a new tab. It must use WebKit's `configuration` so
    /// window.opener (OAuth sign-in flows) keeps working.
    func adoptPopup(configuration: WKWebViewConfiguration, url: String, background: Bool,
                    opener: TabController) -> WKWebView? {
        guard let host, let tab = state.newTabFromLink(url: url, opener: opener.tab, select: !background) else { return nil }
        let page = WebKitTab(configuration: configuration)
        let controller = TabController(tab: tab, state: state, host: host, page: page)
        controllers[tab.id] = controller
        surface.park(controller.hostView)
        controller.hostView.frame = surface.bounds
        ExtensionManager.shared.tabOpened(controller)
        return page.webView
    }
}

/// Re-arming observation helper for AppKit controllers.
@MainActor
func observeState(_ track: @escaping @MainActor () -> Void, onChange: @escaping @MainActor () -> Void) {
    withObservationTracking(track) {
        Task { @MainActor in
            onChange()
            observeState(track, onChange: onChange)
        }
    }
}

/// No open tabs in this Space.
/// What a Space shows with no tabs open: Ikago's mark, the Space, and the next steps (a new tab, the last closed tab,
/// recent sites, History and Bookmarks) instead of an empty page.
private struct EmptyTabView: View {
    let state: BrowserState
    let commands: () -> BrowserCommands?

    var body: some View {
        let colors = state.palette
        VStack(spacing: 22) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().interpolation(.high).frame(width: 72, height: 72)
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
            VStack(spacing: 6) {
                Text(state.activeSpace.name)
                    .font(.system(size: 24, weight: .semibold)).foregroundStyle(colors.text)
                Text("No open tabs in this Space")
                    .font(.system(size: 13)).foregroundStyle(colors.secondary)
            }
            HStack(spacing: 8) {
                Button { commands()?.newTab() } label: { Label("New Tab", systemImage: "plus") }
                    .buttonStyle(SettingsButtonStyle(prominent: true))
                if !state.closed.isEmpty {
                    Button { withAnimation(.ikago) { state.reopenClosedTab() } } label: {
                        Label("Reopen Closed Tab", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(SettingsButtonStyle())
                }
            }
            .controlSize(.large)
            let recent = recentSites
            if !recent.isEmpty {
                HStack(spacing: 10) {
                    ForEach(recent, id: \.url) { visit in
                        Button { (commands() as? BrowserWindowController)?.open(visit.url, inNewTab: true) } label: {
                            VStack(spacing: 6) {
                                FaviconView(pageURL: visit.url, size: 22)
                                    .frame(width: 46, height: 46)
                                    .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(colors.hover))
                                Text(URL(string: visit.url)?.host()?.replacingOccurrences(of: "www.", with: "") ?? visit.title)
                                    .font(.system(size: 11)).foregroundStyle(colors.secondary).lineLimit(1).frame(width: 72)
                            }
                        }
                        .buttonStyle(.plain)
                        .help(visit.title)
                    }
                }
                .padding(.top, 6)
            }
            HStack(spacing: 18) {
                Button("History") { commands()?.openPage(.history) }
                Button("Bookmarks") { commands()?.openPage(.bookmarks) }
            }
            .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(colors.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colors.pageBackground)
        .environment(\.colorScheme, colors.isDark ? .dark : .light)
    }

    /// Up to six recently visited sites, one per host.
    private var recentSites: [Visit] {
        var hosts = Set<String>(), result: [Visit] = []
        for visit in state.history.prefix(300) where AddressResolver.isWebURL(visit.url) {
            guard let host = URL(string: visit.url)?.host(), hosts.insert(host).inserted else { continue }
            result.append(visit)
            if result.count == 6 { break }
        }
        return result
    }
}
