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
    var themeEditingSpaceID: UUID?
    var activeTabID: String?
    var closed: [SavedTab] = []
    var history: [Visit] = [] { didSet { knownSitesGeneration &+= 1 } }
    /// Tabs whose next committed visit was typed (or chosen) in the address field.
    @ObservationIgnored var typedNavigations = Set<String>()
    var bookmarks: [Bookmark] = [] { didSet { knownSitesGeneration &+= 1 } }
    /// Bumped whenever history or bookmarks change, so caches derived from them (SiteSafety) know to rebuild.
    @ObservationIgnored private(set) var knownSitesGeneration = 0
    var bookmarkFolders: [BookmarkFolder] = []
    var browserPreferences = BrowserPreferences() {
        didSet {
            if browserPreferences.pageIntelligence == true && oldValue.pageIntelligence != true { preparePageAssistantToolbar() }
            scheduleSave()
        }
    }
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
    static let defaultSidebarWidth: Double = 260
    var searchShowsHistory = true { didSet { scheduleSave() } }
    var addressStyle: AddressStyle = .integrated { didSet { scheduleSave() } }
    /// Inspect Element and ⌥⌘I.
    var developerTools = true { didSet { scheduleSave() } }
    /// Which controls the sidebar shows, in order (Settings ▸ Customize).
    var chromeLayout = ChromeLayout() { didSet { scheduleSave() } }
    var newTabMode: NewTabMode = .commandBar { didSet { scheduleSave() } }
    var focusAddressBarOnNewTab = false { didSet { scheduleSave() } }
    var homepage = "" { didSet { scheduleSave() } }
    /// The extension whose new-tab page (e.g. Momentum) new tabs show.
    var newTabExtensionID: String? { didSet { scheduleSave() } }
    var searchEngine: SearchEngine = .duckduckgo { didSet { scheduleSave() } }
    var sidebarVisible = true { didSet { scheduleSave() } }
    /// Full screen: the page goes edge to edge and the sidebar slides in from its edge on demand.
    /// Not saved; the window sets it.
    var isImmersive = false
    /// "Allow Once" permission grants by tab (`VisitGrant`); not saved.
    var visitGrants: [String: VisitGrant] = [:]
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
    /// Recent selection order per Space, used when a tab closes so its opener is restored first.
    @ObservationIgnored var recentTabSelections: [UUID: [String]] = [:]
    /// Set when both session files were unreadable (they stay on disk untouched).
    var restoreWarning: String?
    /// A new profile shows the welcome page once its window opens.
    @ObservationIgnored var pendingWelcome = false
    var settingsCategory: SettingsCategory = .general
    /// The sub-page shown in each Settings category (`SettingsSubpage`), for this window's session.
    var settingsSubpage: [SettingsCategory: String] = [:]
    /// A Settings section to scroll to and outline once Settings shows it (the address field's setting actions).
    var pendingSettingsSection: String?
    @ObservationIgnored let importer = BrowserImportModel()
    /// Another regular window's state: the first window's (`primary`) saves the session, this one's tabs included, and
    /// both share Spaces, settings, history and bookmarks (`BrowserState+Windows`). Nil for the first window.
    @ObservationIgnored weak var primary: BrowserState?
    /// On the first window's state: the other regular windows' states, saved in `Session.windows`.
    @ObservationIgnored var windowStates: [BrowserState] = []
    /// The window's frame on screen, saved for windows after the first (the first uses AppKit's autosave).
    @ObservationIgnored var windowFrame: CGRect?
    /// Windows a restored session had beyond the first; the app opens them after the first window.
    @ObservationIgnored var pendingWindows: [WindowSession] = []
    /// Recently closed windows, newest first; kept by the first window's state only (`recordClosedWindow`).
    var closedWindows: [WindowSession] = []

    @ObservationIgnored let store: SessionStore
    /// The session last handed to the store, so an unchanged scheduled save is skipped.
    @ObservationIgnored var lastSavedSession: Session?
    @ObservationIgnored var saveTask: Task<Void, Never>?
    /// Set once the window/app is going away: browser teardown must not edit or save the session.
    @ObservationIgnored var isFrozen = false
    /// A private window: nothing is saved (session, history), pages use in-memory storage.
    @ObservationIgnored private(set) var isPrivate = false
    /// This window is a web app's (`WebApps`): one page, no sidebar or tabs, and never part of the saved session.
    var webApp: WebApp?
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
        closedWindows = []
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
    /// Keyboard order follows standalone pins interleaved with group sections.
    var sidebarOrder: [TabItem] { orderedSidebarTabs }

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
        // Tabs across the top: placing beside a pinned tab would put the new one at the row's far left (pins come
        // first in `tabs`), so it opens on the right like any new tab.
        let besidePin = usesTabsLayout && [target, anchor].contains { id in id.flatMap { self.tab($0) }?.pinned == true }
        let target = besidePin ? nil : target, anchor = besidePin ? nil : anchor
        if let target, let index = tabs.firstIndex(where: { $0.id == target && $0.spaceID == spaceID }) {
            tabs.insert(tab, at: index)
        } else if let anchor, let index = tabs.firstIndex(where: { $0.id == anchor && $0.spaceID == spaceID }) {
            tabs.insert(tab, at: index + 1)
        } else {
            let matching = tabs.indices.filter { tabs[$0].spaceID == spaceID && !tabs[$0].pinned && tabs[$0].folderID == folder }
            let index = effectiveNewTabPosition == .top ? matching.first : matching.last.map { $0 + 1 }
            tabs.insert(tab, at: index ?? tabs.endIndex)
        }
        if select {
            // Chrome remembers the tab you were on as a new tab's opener: closing it straight away goes back there.
            let previous = activeTabID.flatMap { self.tab($0) }.flatMap { $0.spaceID == spaceID ? $0.id : nil }
            self.select(tab.id)
            tab.openerID = previous
        }
        scheduleSave()
        return tab
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
        // Like Chrome: back in its Space, its group and its place, selected. A fresh identity; the page and pin state are kept.
        let space = last.space.flatMap(UUID.init(uuidString:)).flatMap { id in spaces.first { $0.id == id }?.id } ?? activeSpaceID
        let folder = last.folder.flatMap { id in folders.first { $0.id == id && $0.spaceID == space }?.id }
        // The same identity when it's free, so tabs closed after this one (which name it as their neighbour) find
        // their place again when they are reopened too.
        let id = tabs.contains { $0.id == last.id } ? UUID().uuidString : last.id
        let tab = TabItem(id: id, url: InternalPage(url: last.url)?.url ?? last.url, title: last.title, pinned: last.pinned,
                          spaceID: space, folderID: last.pinned ? nil : folder)
        tab.faviconURL = last.favicon.flatMap(URL.init(string:))
        tab.history = last.history
        tab.pinAsRow = last.pinAsRow ?? false
        tab.pinAfterFolderID = last.pinAfterFolderID
        // Its neighbour may have closed too: follow the closed tabs' own neighbours back to one that is open, like
        // Chrome restoring a run of closed tabs in their order.
        var anchor = last.after
        var lost = false  // the chain ends at a tab that is gone for good: put it at the end
        var steps = 0
        while let current = anchor, !tabs.contains(where: { $0.id == current }) {
            guard steps < closed.count, let record = closed.first(where: { $0.id == current }) else { lost = true; break }
            anchor = record.after
            steps += 1
        }
        if !lost, let anchor, let index = tabs.firstIndex(where: { $0.id == anchor && $0.spaceID == space }) {
            tabs.insert(tab, at: index + 1)
        } else if !lost, anchor == nil, let index = tabs.firstIndex(where: { $0.spaceID == space }) {
            tabs.insert(tab, at: index)  // it was its Space's first tab
        } else {
            tabs.append(tab)  // its neighbour has closed too
        }
        tabs = tabs.filter(\.pinned) + tabs.filter { !$0.pinned }
        select(tab.id)
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
        tab.pinAsRow = tab.pinned
        tab.pinAfterFolderID = nil
        tab.folderID = nil
        // Keep pinned tabs grouped first.
        tabs = tabs.filter(\.pinned) + tabs.filter { !$0.pinned }
        scheduleSave()
    }

    /// Moves a tab before `targetID` (or to the end of its group) as pinned or regular,
    /// inside `folderID` or loose. Tabs of other Spaces keep their places.
    func move(_ id: String, before targetID: String?, pinned: Bool, folderID: String? = nil) {
        guard let moving = tab(id), id != targetID else { return }
        if moving.folderID == nil, !moving.pinned { keepGroupsInPlace(leaving: id) }
        moving.pinned = pinned
        if !pinned { moving.pinAsRow = false; moving.pinAfterFolderID = nil }
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
