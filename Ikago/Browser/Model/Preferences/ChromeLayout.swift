import Foundation

/// A control that can be placed in the sidebar (Settings ▸ Sidebar & Toolbar ▸ Customize).
enum ChromeItem: String, Codable, CaseIterable, Identifiable {
    case sidebarToggle, back, forward, reload, newTab, spaces, newSpace, history, downloads, settings, bookmarks, notes
    case share, assistant, devices, siteInfo
    /// The Space's tab groups as a menu: hidden ones to show again, and the others to go to.
    case tabGroups

    var id: String { rawValue }

    var name: String {
        switch self {
        case .sidebarToggle: "Sidebar"
        case .back: "Back"
        case .forward: "Forward"
        case .reload: "Reload"
        case .newTab: "New Tab"
        case .spaces: "Spaces"
        case .newSpace: "New Space"
        case .bookmarks: "Bookmarks"
        case .history: "History"
        case .downloads: "Downloads"
        case .settings: "Settings"
        case .notes: "Notes"
        case .assistant: "Page Assistant"
        case .share: "Share"
        case .devices: "Other Devices"
        case .siteInfo: "Site & Extensions"
        case .tabGroups: "Tab Groups"
        }
    }

    /// Controls whose popover or menu opens from the button itself, so they never move into a More menu.
    var anchorsPopover: Bool {
        switch self {
        case .spaces, .downloads, .devices, .siteInfo, .share, .tabGroups: true
        default: false
        }
    }

    var symbol: String {
        switch self {
        case .sidebarToggle: "sidebar.left"
        case .back: "chevron.left"
        case .forward: "chevron.right"
        case .reload: "arrow.clockwise"
        case .newTab: "plus"
        case .spaces: "square.stack"
        case .newSpace: "plus.square.on.square"
        case .bookmarks: "bookmark"
        case .history: "clock"
        case .downloads: "arrow.down.circle"
        case .settings: "gearshape"
        case .notes: "note.text"
        case .assistant: "sparkles"
        case .share: "square.and.arrow.up"
        case .devices: "iphone"
        case .tabGroups: "square.stack.3d.down.right"
        case .siteInfo: "puzzlepiece.extension"
        }
    }
}

/// The places items can go: the left, centre and right of the sidebar's top row and of its bottom bar (`sidebarTop` is
/// the top row's right and `sidebarBottom` the bottom bar's centre, where every control sat before rows had three
/// places); the left and right of the Top Tabs toolbar; and the foot of the icons-only sidebar (the rail).
/// Each layout has its own places, so an item can sit in the sidebar and in the toolbar at once.
enum ChromeZone: String, Codable, CaseIterable {
    case sidebarTopLeading, sidebarTopCenter, sidebarTop
    case sidebarBottomLeading, sidebarBottom, sidebarBottomTrailing
    /// Top Tabs: the window's left and right edges, and either side of the address field.
    case toolbarLeading, toolbarNearLeading, toolbarNearTrailing, toolbarTrailing
    /// The Sidebar layout's address bar above the page: either side of the address.
    case pageBarLeading, pageBarTrailing
    case rail

    var allowed: [ChromeItem] { ChromeItem.allCases }
    var isTop: Bool {
        [.sidebarTopLeading, .sidebarTopCenter, .sidebarTop].contains(self) || Self.toolbarRow.contains(self) || Self.pageBarRow.contains(self)
    }
    var title: String {
        switch self {
        case .sidebarTopLeading, .sidebarBottomLeading: "Left"
        case .sidebarTopCenter, .sidebarBottom: "Center"
        case .sidebarTop, .sidebarBottomTrailing: "Right"
        case .toolbarLeading: "Left edge"
        case .toolbarNearLeading: "Left of the address"
        case .toolbarNearTrailing: "Right of the address"
        case .toolbarTrailing: "Right edge"
        case .pageBarLeading: "Left of the address"
        case .pageBarTrailing: "Right of the address"
        case .rail: "Icons-only sidebar"
        }
    }
    /// The places an item moves between: placing it in one takes it out of the others in its family only.
    var family: [ChromeZone] {
        switch self {
        case .toolbarLeading, .toolbarNearLeading, .toolbarNearTrailing, .toolbarTrailing: Self.toolbarRow
        case .rail: [.rail]
        case .pageBarLeading, .pageBarTrailing: Self.pageBarRow
        default: Self.topRow + Self.bottomRow
        }
    }
    static let topRow: [ChromeZone] = [.sidebarTopLeading, .sidebarTopCenter, .sidebarTop]
    static let bottomRow: [ChromeZone] = [.sidebarBottomLeading, .sidebarBottom, .sidebarBottomTrailing]
    static let toolbarRow: [ChromeZone] = [.toolbarLeading, .toolbarNearLeading, .toolbarNearTrailing, .toolbarTrailing]
    static let pageBarRow: [ChromeZone] = [.pageBarLeading, .pageBarTrailing]
}

/// Which controls show where, in order. Anything not placed is hidden.
struct ChromeLayout: Codable, Equatable {
    var sidebarTop: [ChromeItem] = [.sidebarToggle, .back, .forward, .reload]
    var sidebarBottom: [ChromeItem] = [.spaces, .newSpace]
    /// The other places in each row (optional in saved sessions; empty by default).
    var topLeading: [ChromeItem] = []
    var topCenter: [ChromeItem] = []
    var bottomLeading: [ChromeItem] = []
    var bottomTrailing: [ChromeItem] = []
    /// Top Tabs: the toolbar's two sides, the address centred between them.
    var toolbarLeading: [ChromeItem] = Self.navigation
    var toolbarTrailing: [ChromeItem] = []
    /// Top Tabs: controls right beside the address field, on its left and right (empty by default).
    var toolbarNearLeading: [ChromeItem] = []
    var toolbarNearTrailing: [ChromeItem] = []
    /// The Sidebar layout's address bar above the page: controls either side of the address (empty by default: the
    /// sidebar keeps the navigation).
    var pageBarLeading: [ChromeItem] = []
    var pageBarTrailing: [ChromeItem] = []
    /// The controls at the foot of the icons-only sidebar.
    var rail: [ChromeItem] = [.sidebarToggle]
    var sidebarShowsAddress = true
    var sidebarShowsNewTab = true
    /// Reload and the site card's button inside the address field, beside any copies placed in a toolbar.
    var addressShowsReload = true
    var addressShowsSiteInfo = true

    /// Controls the Top Tabs toolbar keeps left of the address when taken from an older sidebar layout.
    static let navigation: [ChromeItem] = [.sidebarToggle, .back, .forward, .reload]

    init() {}

    /// Saved layouts from before a field existed keep working; the retired Top Bar's zones are ignored.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ChromeLayout()
        // Skip items this version no longer has, so one retired control can't fail the whole session.
        func items(_ key: CodingKeys) throws -> [ChromeItem]? {
            try c.decodeIfPresent([String].self, forKey: key)?.compactMap(ChromeItem.init(rawValue:))
        }
        sidebarTop = try items(.sidebarTop) ?? d.sidebarTop
        sidebarBottom = try items(.sidebarBottom) ?? d.sidebarBottom
        topLeading = try items(.topLeading) ?? []
        topCenter = try items(.topCenter) ?? []
        bottomLeading = try items(.bottomLeading) ?? []
        bottomTrailing = try items(.bottomTrailing) ?? []
        sidebarShowsAddress = try c.decodeIfPresent(Bool.self, forKey: .sidebarShowsAddress) ?? true
        sidebarShowsNewTab = try c.decodeIfPresent(Bool.self, forKey: .sidebarShowsNewTab) ?? true
        // Layouts from before the toolbar had its own places: it showed the sidebar's top row, navigation on the left.
        let top = topLeading + topCenter + sidebarTop
        toolbarLeading = try items(.toolbarLeading) ?? top.filter(Self.navigation.contains)
        toolbarTrailing = try items(.toolbarTrailing) ?? top.filter { !Self.navigation.contains($0) }
        toolbarNearLeading = try items(.toolbarNearLeading) ?? []
        toolbarNearTrailing = try items(.toolbarNearTrailing) ?? []
        pageBarLeading = try items(.pageBarLeading) ?? []
        pageBarTrailing = try items(.pageBarTrailing) ?? []
        rail = try items(.rail) ?? d.rail
        addressShowsReload = try c.decodeIfPresent(Bool.self, forKey: .addressShowsReload) ?? true
        addressShowsSiteInfo = try c.decodeIfPresent(Bool.self, forKey: .addressShowsSiteInfo) ?? true
    }

    subscript(zone: ChromeZone) -> [ChromeItem] {
        get {
            switch zone {
            case .sidebarTopLeading: topLeading
            case .sidebarTopCenter: topCenter
            case .sidebarTop: sidebarTop
            case .sidebarBottomLeading: bottomLeading
            case .sidebarBottom: sidebarBottom
            case .sidebarBottomTrailing: bottomTrailing
            case .toolbarLeading: toolbarLeading
            case .toolbarTrailing: toolbarTrailing
            case .toolbarNearLeading: toolbarNearLeading
            case .toolbarNearTrailing: toolbarNearTrailing
            case .pageBarLeading: pageBarLeading
            case .pageBarTrailing: pageBarTrailing
            case .rail: rail
            }
        }
        set {
            switch zone {
            case .sidebarTopLeading: topLeading = newValue
            case .sidebarTopCenter: topCenter = newValue
            case .sidebarTop: sidebarTop = newValue
            case .sidebarBottomLeading: bottomLeading = newValue
            case .sidebarBottom: sidebarBottom = newValue
            case .sidebarBottomTrailing: bottomTrailing = newValue
            case .toolbarLeading: toolbarLeading = newValue
            case .toolbarTrailing: toolbarTrailing = newValue
            case .toolbarNearLeading: toolbarNearLeading = newValue
            case .toolbarNearTrailing: toolbarNearTrailing = newValue
            case .pageBarLeading: pageBarLeading = newValue
            case .pageBarTrailing: pageBarTrailing = newValue
            case .rail: rail = newValue
            }
        }
    }

    /// Everything in the top row or the bottom bar, left to right.
    var topItems: [ChromeItem] { topLeading + topCenter + sidebarTop }
    var bottomItems: [ChromeItem] { bottomLeading + sidebarBottom + bottomTrailing }

    /// Moves (or adds) `item` into `zone` before `target`, or at the end. An item appears at most once per family.
    mutating func place(_ item: ChromeItem, in zone: ChromeZone, before target: ChromeItem? = nil) {
        guard zone.allowed.contains(item), item != target else { return }
        for other in zone.family { self[other].removeAll { $0 == item } }
        var items = self[zone]
        let index = target.flatMap { items.firstIndex(of: $0) } ?? items.count
        items.insert(item, at: index)
        self[zone] = items
    }

    /// Takes `item` out of `zones` (every place by default).
    mutating func remove(_ item: ChromeItem, from zones: [ChromeZone] = ChromeZone.allCases) {
        for zone in zones { self[zone].removeAll { $0 == item } }
    }

    /// Adds a control both layouts should show (the sidebar's top row and the toolbar's right), where it is missing.
    mutating func add(_ item: ChromeItem) {
        if !contains(item, in: .sidebarTop) { place(item, in: .sidebarTop) }
        if !ChromeZone.toolbarRow.contains(where: { contains(item, in: $0) }) { place(item, in: .toolbarTrailing) }
    }

    func contains(_ item: ChromeItem) -> Bool {
        ChromeZone.allCases.contains { self[$0].contains(item) }
    }

    /// Whether `item` is placed in `zone`'s family.
    func contains(_ item: ChromeItem, in zone: ChromeZone) -> Bool {
        zone.family.contains { self[$0].contains(item) }
    }

    /// Items that can still be added to `zones`.
    func available(in zones: [ChromeZone] = ChromeZone.topRow + ChromeZone.bottomRow) -> [ChromeItem] {
        let used = Set(zones.flatMap { self[$0] })
        return ChromeItem.allCases.filter { !used.contains($0) }
    }
}
