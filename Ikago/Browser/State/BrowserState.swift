import Foundation
import Observation

/// Single source of truth for tabs, splits, history and preferences. Pure model: the
/// window layer observes it and reconciles live pages (see WebContentViewController).
@MainActor
@Observable
final class BrowserState {
    var tabs: [TabItem] = [] { didSet { tabsByID = Self.index(tabs) } }
    /// `tabs` by ID (the first tab with each ID, like a linear search), rebuilt whenever `tabs` changes.
    @ObservationIgnored private var tabsByID: [String: TabItem] = [:]
    var activeTabID: String?
    var closed: [SavedTab] = []
    var history: [Visit] = [] { didSet { knownSitesGeneration &+= 1 } }
    /// Tabs whose next committed visit was typed (or chosen) in the address field.
    @ObservationIgnored var typedNavigations = Set<String>()
    var bookmarks: [Bookmark] = [] { didSet { knownSitesGeneration &+= 1 } }
    /// Bumped whenever history or bookmarks change, so caches derived from them (SiteSafety) know to rebuild.
    @ObservationIgnored private(set) var knownSitesGeneration = 0
    var bookmarkFolders: [BookmarkFolder] = []
    var browserPreferences = BrowserPreferences() { didSet { scheduleSave() } }
    var tabLayout: TabLayout = .vertical { didSet { scheduleSave() } }
    var colorMode: ColorMode = .system { didSet { scheduleSave() } }
    /// macOS's own appearance, kept current by the window controller.
    var systemIsDark = false
    var sidebarWidth: Double = BrowserState.defaultSidebarWidth { didSet { scheduleSave() } }
    /// Liquid Glass on floating surfaces; off draws flat panels.
    var useGlass = true { didSet { scheduleSave() } }
    /// Gap between the window edge and the sidebar/page, in points (0 = edge to edge).
    var frameInset: Double = BrowserState.defaultFrameInset { didSet { scheduleSave() } }
    static let defaultFrameInset: Double = 4
    /// Space between the sidebar and the page (the resize handle lives in it).
    var sidebarGap: Double = BrowserState.defaultSidebarGap { didSet { scheduleSave() } }
    static let defaultSidebarGap: Double = 6
    /// Top Bar layout: island height and outline width (Settings ▸ Appearance).
    var barHeight: Double = BrowserState.defaultBarHeight { didSet { scheduleSave() } }
    var barBorder: Double = 0 { didSet { scheduleSave() } }
    static let defaultBarHeight: Double = 28
    /// Space between the island's title row and the page (Top Bar layout).
    var barGap: Double = BrowserState.defaultBarGap { didSet { scheduleSave() } }
    static let defaultBarGap: Double = 6
    /// Top bar is a rounded panel like the page, instead of tinting the whole window frame.
    var barRounded = false { didSet { scheduleSave() } }
    static let defaultSidebarWidth: Double = 260
    var searchShowsHistory = true { didSet { scheduleSave() } }
    var addressStyle: AddressStyle = .integrated { didSet { scheduleSave() } }
    /// Top bar takes the page's theme color (Settings ▸ Appearance).
    var tintBarWithPage = true { didSet { scheduleSave() } }
    /// Inspect Element and ⌥⌘I.
    var developerTools = true { didSet { scheduleSave() } }
    /// Which controls the top bar and sidebar show, in order (Settings ▸ Customize).
    var chromeLayout = ChromeLayout() { didSet { scheduleSave() } }
    var newTabMode: NewTabMode = .commandBar { didSet { scheduleSave() } }
    var focusAddressBarOnNewTab = false { didSet { scheduleSave() } }
    var homepage = "" { didSet { scheduleSave() } }
    /// The extension whose new-tab page (e.g. Momentum) new tabs show.
    var newTabExtensionID: String? { didSet { scheduleSave() } }
    var searchEngine: SearchEngine = .duckduckgo { didSet { scheduleSave() } }
    var sidebarVisible = true { didSet { scheduleSave() } }
    /// Full screen: the page goes edge to edge and the sidebar or top bars slide in from their edge on demand.
    /// Not saved; the window sets it.
    var isImmersive = false
    /// Full screen: how far revealed bars start below the top, so the menu bar never covers them.
    var immersiveChromeTop: CGFloat = 0
    /// Split groups: tabs shown side by side (2–4 each). A group is shown whenever one of its
    /// tabs is active; a tab is in at most one group.
    var splits: [[String]] = [] { didSet { splitIndex = Self.splitIndex(splits) } }
    /// Tab ID → its (first) group's index in `splits`, rebuilt whenever `splits` changes.
    @ObservationIgnored private(set) var splitIndex: [String: Int] = [:]
    var splitLayout: SplitLayout = .columns
    var spaces: [SpaceProfile] = [.defaultSpace]
    var activeSpaceID = SpaceProfile.defaultSpace.id
    var folders: [TabFolder] = []
    /// Each Space's last active tab, restored when switching back to it.
    var lastActiveTab: [UUID: String] = [:]
    /// Set when both session files were unreadable (they stay on disk untouched).
    var restoreWarning: String?
    /// A new profile shows the welcome page once its window opens.
    @ObservationIgnored var pendingWelcome = false
    var settingsCategory: SettingsCategory = .general
    @ObservationIgnored let importer = BrowserImportModel()

    @ObservationIgnored let store: SessionStore
    /// The session last handed to the store, so an unchanged scheduled save is skipped.
    @ObservationIgnored var lastSavedSession: Session?
    @ObservationIgnored var saveTask: Task<Void, Never>?
    /// Set once the window/app is going away: browser teardown must not edit or save the session.
    @ObservationIgnored var isFrozen = false
    /// A private window: nothing is saved (session, history), pages use in-memory storage.
    @ObservationIgnored private(set) var isPrivate = false
    let privateProfileID = "Private-" + UUID().uuidString

    init(store: SessionStore = .standard) {
        self.store = store
        PublicSuffix.warm()
        restore()
    }

    /// A private window's state: `main`'s settings and active Space look, no tabs or history.
    init(privateFrom main: BrowserState) {
        store = SessionStore(directory: FileManager.default.temporaryDirectory.appending(path: "IkagoPrivate-\(UUID())"))
        isPrivate = true
        var session = main.snapshot()
        session.tabs = []; session.active = nil; session.closed = []; session.history = []
        session.splits = nil; session.folders = []; session.lastActiveTab = nil
        session.spaces = [main.activeSpace]; session.activeSpace = main.activeSpaceID
        apply(session)
        colorMode = .dark  // private windows always look dark, so they're easy to tell apart
        history = []
        systemIsDark = main.systemIsDark
    }

    // MARK: Derived

    var activeTab: TabItem? { activeTabID.flatMap { tab($0) } }
    var activeSpace: SpaceProfile { spaces.first { $0.id == activeSpaceID } ?? .defaultSpace }

    var isDark: Bool { colorMode == .dark || (colorMode == .system && systemIsDark) }
    var palette: Palette { Palette(colors: activeSpace.resolvedColors, isDark: isDark, glass: useGlass) }

    // The active Space only: what the sidebar shows and what keyboard selection walks.
    var spaceTabs: [TabItem] { tabs.filter { $0.spaceID == activeSpaceID } }
    var pinnedTabs: [TabItem] { spaceTabs.filter(\.pinned) }
    var regularTabs: [TabItem] { spaceTabs.filter { !$0.pinned } }
    var looseTabs: [TabItem] { regularTabs.filter { $0.folderID == nil } }
    var spaceFolders: [TabFolder] { folders.filter { $0.spaceID == activeSpaceID } }
    func tabs(in folder: TabFolder) -> [TabItem] { regularTabs.filter { $0.folderID == folder.id } }
    /// Sidebar order: pinned, then each folder's tabs, then loose tabs.
    var sidebarOrder: [TabItem] { pinnedTabs + spaceFolders.flatMap { tabs(in: $0) } + looseTabs }

    /// Tabs currently on screen, in pane order.
    var visibleTabIDs: [String] {
        guard let active = activeTabID else { return [] }
        return splitGroup(of: active) ?? [active]
    }

    func tab(_ id: String) -> TabItem? {
        _ = tabs  // still tracked by observers, as when it searched the array
        return tabsByID[id]
    }
    private static func index(_ tabs: [TabItem]) -> [String: TabItem] {
        Dictionary(tabs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: Tabs

    @discardableResult
    func newTab(url: String, select: Bool = true, after anchor: String? = nil, before target: String? = nil,
                in destination: UUID? = nil, folderID: String? = nil) -> TabItem? {
        let spaceID = destination ?? activeSpaceID
        guard tabs.count < Session.maxTabs, spaces.contains(where: { $0.id == spaceID }) else { return nil }
        let folder = folderID.flatMap { id in folders.first { $0.id == id && $0.spaceID == spaceID }?.id }
        let tab = TabItem(url: url, spaceID: spaceID, folderID: folder)
        tab.shouldStartInBackground = browserPreferences.loadBackgroundTabs ?? true
        if let target, let index = tabs.firstIndex(where: { $0.id == target && $0.spaceID == spaceID }) {
            tabs.insert(tab, at: index)
        } else if let anchor, let index = tabs.firstIndex(where: { $0.id == anchor && $0.spaceID == spaceID }) {
            tabs.insert(tab, at: index + 1)
        } else {
            let matching = tabs.indices.filter { tabs[$0].spaceID == spaceID && !tabs[$0].pinned && tabs[$0].folderID == folder }
            let index = effectiveNewTabPosition == .top ? matching.first : matching.last.map { $0 + 1 }
            tabs.insert(tab, at: index ?? tabs.endIndex)
        }
        if select { self.select(tab.id) }
        scheduleSave()
        return tab
    }

    /// Selects a tab, switching to its Space first if needed.
    func select(_ id: String) {
        guard let tab = tab(id) else { return }
        if tab.spaceID != activeSpaceID { enterSpace(tab.spaceID) }
        reopenFolderIfClosed(containing: id)
        activeTabID = id
        scheduleSave()
    }

    func selectTab(at index: Int) {
        let ordered = navigationOrder
        guard !ordered.isEmpty else { return }
        select(ordered[index < 0 ? ordered.count - 1 : min(index, ordered.count - 1)].id)
    }

    func selectAdjacent(_ offset: Int) {
        let ordered = navigationOrder
        guard let current = ordered.firstIndex(where: { $0.id == activeTabID }), !ordered.isEmpty else { return }
        select(ordered[(current + offset + ordered.count) % ordered.count].id)
    }

    func closeTab(_ id: String, removingPin: Bool = false) {
        guard !isFrozen, let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        if tabs[index].pinned && !removingPin {
            let pin = tabs[index]
            let partner = splitGroup(of: id)?.first { $0 != id }
            removeFromSplits([id])
            if activeTabID == id {
                activeTabID = partner ?? sidebarOrder.first { $0.id != id && !$0.isHibernating }?.id
            }
            pin.isHibernating = true
            scheduleSave()
            return
        }
        // Next active tab: the neighbour in the same Space's sidebar order.
        let order = tabs[index].spaceID == activeSpaceID ? navigationOrder : []
        let position = order.firstIndex { $0.id == id } ?? 0
        let neighbours = order.filter { $0.id != id }
        let tab = tabs.remove(at: index)
        if AddressResolver.isPageURL(tab.url) || ExtensionURL.isExtension(tab.url) || Self.isReopenableInternalPage(tab.url) {
            closed = Array(([tab.saved] + closed).prefix(Session.maxClosed))
        }
        let partner = splitGroup(of: id)?.first { $0 != id }
        removeFromSplits([id])
        if activeTabID == id {
            activeTabID = partner ?? (neighbours.isEmpty ? nil : neighbours[min(position, neighbours.count - 1)].id)
        }
        scheduleSave()
    }

    func reopenClosedTab() {
        guard let last = closed.first else { return }
        // Ikago's own pages keep one tab per Space: reopening one that's open again just shows it.
        if Self.isReopenableInternalPage(last.url), let open = spaceTabs.first(where: { InternalPage(url: $0.url) == InternalPage(url: last.url) }) {
            closed.removeFirst()
            select(open.id)
            return
        }
        guard tabs.count < Session.maxTabs else { return }
        closed.removeFirst()
        // Fresh identity, preserved page and pin state (legacy behaviour).
        let tab = TabItem(url: InternalPage(url: last.url)?.url ?? last.url, title: last.title, pinned: last.pinned, spaceID: activeSpaceID)
        tab.faviconURL = last.favicon.flatMap(URL.init(string:))
        tabs.append(tab)
        activeTabID = tab.id
        scheduleSave()
    }

    /// Settings, History, Downloads and Bookmarks come back with ⌘⇧T; an empty split slot and the welcome page don't.
    static func isReopenableInternalPage(_ url: String) -> Bool {
        guard let page = InternalPage(url: url) else { return false }
        return page != .splitEmpty && page != .welcome
    }

    func togglePin(_ id: String) {
        guard let tab = tab(id) else { return }
        tab.pinned.toggle()
        tab.folderID = nil
        // Keep pinned tabs grouped first.
        tabs = tabs.filter(\.pinned) + tabs.filter { !$0.pinned }
        scheduleSave()
    }

    /// Moves a tab before `targetID` (or to the end of its group) as pinned or regular,
    /// inside `folderID` or loose. Tabs of other Spaces keep their places.
    func move(_ id: String, before targetID: String?, pinned: Bool, folderID: String? = nil) {
        guard let moving = tab(id), id != targetID else { return }
        moving.pinned = pinned
        moving.folderID = pinned ? nil : folderID
        tabs.removeAll { $0.id == id }
        if let targetID, let index = tabs.firstIndex(where: { $0.id == targetID }) {
            tabs.insert(moving, at: index)
        } else if let last = tabs.lastIndex(where: { $0.spaceID == moving.spaceID && $0.pinned == pinned
                                                    && $0.folderID == moving.folderID }) {
            tabs.insert(moving, at: last + 1)
        } else {
            tabs.append(moving)
        }
        tabs = tabs.filter(\.pinned) + tabs.filter { !$0.pinned }
        scheduleSave()
    }

    // MARK: Navigation reports (from WebKit)

    func recordVisit(tabID: String, url: String) {
        guard !isPrivate, AddressResolver.isWebURL(url), let tab = tab(tabID) else { return }
        let previous = history.first { $0.url == url }
        let typed = typedNavigations.remove(tabID) != nil
        let visit = Visit(url: url, title: tab.title, time: UInt64(Date().timeIntervalSince1970 * 1000),
                          visits: min(1_000_000, (previous?.visits ?? 1) + (previous == nil ? 0 : 1)),
                          typed: min(1_000_000, (previous?.typed ?? 0) + (typed ? 1 : 0)))
        history = Array(([visit] + history.filter { $0.url != url }).prefix(Session.maxHistory))
        scheduleSave()
    }

    func updateTitle(tabID: String, title: String) {
        let title = String(title.prefix(2048))
        // Pages report their title often; an unchanged one rewrites nothing and saves nothing.
        guard let tab = tab(tabID), tab.title != title else { return }
        tab.title = title
        if let i = history.firstIndex(where: { $0.url == tab.url }) { history[i].title = tab.title }
        scheduleSave()
    }

}
