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
    private var emptyView: NSView!
    private(set) var controllers: [String: TabController] = [:]
    private var stopped = false
    private var lastActiveID: String?
    private var mouseMonitor: Any?
    private(set) lazy var hibernation = TabHibernation(content: self)
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
        let empty = FileDropHostingView(rootView: EmptyTabView(state: state))
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
        hibernation.markVisible()
        // In split view, clicking into a pane focuses its tab (the address bar follows it).
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
        _ = state.floatingContentInset
        _ = state.isImmersive
    }

    func shutdown() {
        guard !stopped else { return }
        stopped = true
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
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
        surface.show(visible, layout: state.splitLayout, animate: state.browserPreferences.instantTabSwitching != true && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        surface.highlight(state.activeTabID, views: visible, color: state.palette.nsAccent)
        // Pages poll only while shown; parking or showing one tells it.
        for controller in controllers.values { controller.page?.visibilityChanged() }
        for controller in controllers.values { controller.topInset = state.floatingContentInset }
        hibernation.markVisible()
        for id in state.visibleTabIDs { controllers[id]?.startIfNeeded() }
        for id in state.visibleTabIDs { controllers[id]?.refreshSplitHeader() }
        surface.setPaneBackground(state.isDark ? NSColor(hex: 0x1C1C1E) : .white)
        let switchedTab = state.activeTabID != lastActiveID
        let radius: CGFloat = state.pageCornerRadius
        if WebTabContainerView.cornerRadius != radius {
            WebTabContainerView.cornerRadius = radius
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

    func adoptCEFPopup(_ page: CEFWebTab, url: String, background: Bool, opener: TabController) -> Bool {
        guard let host, let tab = state.newTabFromLink(url: url.isEmpty ? "about:blank" : url, opener: opener.tab, select: !background) else { return false }
        let controller = TabController(tab: tab, state: state, host: host, page: page)
        controllers[tab.id] = controller
        surface.park(controller.hostView)
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
private struct EmptyTabView: View {
    let state: BrowserState

    var body: some View {
        let colors = state.palette
        VStack(spacing: 14) {
            Text(state.activeSpace.name)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(colors.text)
            Text("Press ⌘T to search or open a site")
                .font(.system(size: 14))
                .foregroundStyle(colors.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colors.pageBackground)
        .environment(\.colorScheme, colors.isDark ? .dark : .light)
    }
}
