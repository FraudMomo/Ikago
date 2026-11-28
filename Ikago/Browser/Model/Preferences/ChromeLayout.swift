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

/// The places items can go: the sidebar's top row (after the traffic lights) and its bottom row (centred); the left and
/// right of the Top Tabs toolbar; inside the address field, in every layout; and the foot of the icons-only sidebar.
/// Each layout has its own places, so an item can sit in the sidebar and in the toolbar at once.
enum ChromeZone: String, Codable, CaseIterable {
    case sidebarTop, sidebarBottom
    /// Top Tabs: the toolbar's left and right, the address between them.
    case toolbarLeading, toolbarTrailing
    /// Inside the address field, after the address. Reload and Site & Extensions there show while the pointer is over
    /// it (and while a page loads, or when a site asks for something).
    case address
    case rail

    var allowed: [ChromeItem] { ChromeItem.allCases }
    var isTop: Bool { self != .sidebarBottom && self != .rail }
    var title: String {
        switch self {
        case .sidebarTop: "Top row"
        case .sidebarBottom: "Bottom row"
        case .toolbarLeading: "Left"
        case .toolbarTrailing: "Right"
        case .address: "In the address field"
        case .rail: "Icons-only sidebar"
        }
    }
    /// The places an item moves between: placing it in one takes it out of the others in its family only.
    var family: [ChromeZone] {
        switch self {
        case .sidebarTop, .sidebarBottom: Self.sidebarRows
        case .toolbarLeading, .toolbarTrailing: Self.toolbarRow
        case .address: [.address]
        case .rail: [.rail]
        }
    }
    static let sidebarRows: [ChromeZone] = [.sidebarTop, .sidebarBottom]
    static let toolbarRow: [ChromeZone] = [.toolbarLeading, .toolbarTrailing]
}

/// Which controls show where, in order. Anything not placed is hidden.
struct ChromeLayout: Codable, Equatable {
    var sidebarTop: [ChromeItem] = [.sidebarToggle, .back, .forward, .reload]
    var sidebarBottom: [ChromeItem] = [.spaces, .newSpace]
    /// Top Tabs: the toolbar's two sides, the address between them.
    var toolbarLeading: [ChromeItem] = Self.navigation
    var toolbarTrailing: [ChromeItem] = []
    /// Inside the address field, in every layout.
    var address: [ChromeItem] = [.reload, .siteInfo]
    /// The controls at the foot of the icons-only sidebar.
    var rail: [ChromeItem] = [.sidebarToggle]
    var sidebarShowsAddress = true
    var sidebarShowsNewTab = true

    /// Controls the Top Tabs toolbar keeps left of the address when taken from an older sidebar layout.
    static let navigation: [ChromeItem] = [.sidebarToggle, .back, .forward, .reload]

    init() {}

    /// Places older layouts had, each read once into the place nearest it: a row's left, centre and right into the row,
    /// the toolbar's places beside the address into its sides, and the bar above the page (and the address field's two
    /// switches) into the address field.
    private enum Retired: String, CodingKey {
        case topLeading, topCenter, bottomLeading, bottomTrailing, toolbarNearLeading, toolbarNearTrailing
        case pageBarLeading, pageBarTrailing, addressShowsReload, addressShowsSiteInfo
    }

    /// Saved layouts from before a field existed keep working; the retired Top Bar's zones are ignored.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let old = try decoder.container(keyedBy: Retired.self)
        let d = ChromeLayout()
        // Skip items this version no longer has, so one retired control can't fail the whole session.
        func items<Key: CodingKey>(_ container: KeyedDecodingContainer<Key>, _ key: Key) throws -> [ChromeItem]? {
            try container.decodeIfPresent([String].self, forKey: key)?.compactMap(ChromeItem.init(rawValue:))
        }
        func merged(_ lists: [ChromeItem]?...) -> [ChromeItem] {
            var seen = Set<ChromeItem>()
            return lists.flatMap { $0 ?? [] }.filter { seen.insert($0).inserted }
        }
        sidebarTop = try merged(items(old, .topLeading), items(old, .topCenter), items(c, .sidebarTop) ?? d.sidebarTop)
        sidebarBottom = try merged(items(old, .bottomLeading), items(c, .sidebarBottom) ?? d.sidebarBottom,
                                   items(old, .bottomTrailing))
        sidebarShowsAddress = try c.decodeIfPresent(Bool.self, forKey: .sidebarShowsAddress) ?? true
        sidebarShowsNewTab = try c.decodeIfPresent(Bool.self, forKey: .sidebarShowsNewTab) ?? true
        // Layouts from before the toolbar had its own places: it showed the sidebar's top row, navigation on the left.
        toolbarLeading = try merged(items(c, .toolbarLeading) ?? sidebarTop.filter(Self.navigation.contains),
                                    items(old, .toolbarNearLeading))
        toolbarTrailing = try merged(items(old, .toolbarNearTrailing),
                                     items(c, .toolbarTrailing) ?? sidebarTop.filter { !Self.navigation.contains($0) })
        if let placed = try items(c, .address) {
            address = placed
        } else {
            let reload = try old.decodeIfPresent(Bool.self, forKey: .addressShowsReload) ?? true
            let site = try old.decodeIfPresent(Bool.self, forKey: .addressShowsSiteInfo) ?? true
            address = try merged(reload ? [.reload] : [], site ? [.siteInfo] : [], items(old, .pageBarLeading),
                                 items(old, .pageBarTrailing))
        }
        rail = try items(c, .rail) ?? d.rail
    }

    subscript(zone: ChromeZone) -> [ChromeItem] {
        get {
            switch zone {
            case .sidebarTop: sidebarTop
            case .sidebarBottom: sidebarBottom
            case .toolbarLeading: toolbarLeading
            case .toolbarTrailing: toolbarTrailing
            case .address: address
            case .rail: rail
            }
        }
        set {
            switch zone {
            case .sidebarTop: sidebarTop = newValue
            case .sidebarBottom: sidebarBottom = newValue
            case .toolbarLeading: toolbarLeading = newValue
            case .toolbarTrailing: toolbarTrailing = newValue
            case .address: address = newValue
            case .rail: rail = newValue
            }
        }
    }

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
        if !contains(item, in: .toolbarTrailing) { place(item, in: .toolbarTrailing) }
    }

    func contains(_ item: ChromeItem) -> Bool {
        ChromeZone.allCases.contains { self[$0].contains(item) }
    }

    /// Whether `item` is placed in `zone`'s family.
    func contains(_ item: ChromeItem, in zone: ChromeZone) -> Bool {
        zone.family.contains { self[$0].contains(item) }
    }

    /// Items that can still be added to `zones`.
    func available(in zones: [ChromeZone] = ChromeZone.sidebarRows) -> [ChromeItem] {
        let used = Set(zones.flatMap { self[$0] })
        return ChromeItem.allCases.filter { !used.contains($0) }
    }
}
