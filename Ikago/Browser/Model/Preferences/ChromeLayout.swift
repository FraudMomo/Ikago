import Foundation

/// A control that can be placed in the sidebar (Settings ▸ Sidebar & Toolbar ▸ Customize).
enum ChromeItem: String, Codable, CaseIterable, Identifiable {
    case sidebarToggle, back, forward, reload, newTab, spaces, newSpace, history, downloads, settings, bookmarks, notes
    case share, assistant, devices

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
        }
    }
}

/// The places items can go: the left, centre and right of the sidebar's top row and of its bottom bar. `sidebarTop` is
/// the top row's right and `sidebarBottom` the bottom bar's centre, where every control sat before rows had three places.
enum ChromeZone: String, Codable, CaseIterable {
    case sidebarTopLeading, sidebarTopCenter, sidebarTop
    case sidebarBottomLeading, sidebarBottom, sidebarBottomTrailing

    var allowed: [ChromeItem] { ChromeItem.allCases }
    var isTop: Bool { [.sidebarTopLeading, .sidebarTopCenter, .sidebarTop].contains(self) }
    var title: String {
        switch self {
        case .sidebarTopLeading, .sidebarBottomLeading: "Left"
        case .sidebarTopCenter, .sidebarBottom: "Center"
        case .sidebarTop, .sidebarBottomTrailing: "Right"
        }
    }
    static let topRow: [ChromeZone] = [.sidebarTopLeading, .sidebarTopCenter, .sidebarTop]
    static let bottomRow: [ChromeZone] = [.sidebarBottomLeading, .sidebarBottom, .sidebarBottomTrailing]
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
    var sidebarShowsAddress = true
    var sidebarShowsNewTab = true

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
            }
        }
    }

    /// Everything in the top row or the bottom bar, left to right.
    var topItems: [ChromeItem] { topLeading + topCenter + sidebarTop }
    var bottomItems: [ChromeItem] { bottomLeading + sidebarBottom + bottomTrailing }

    /// Moves (or adds) `item` into `zone` before `target`, or at the end. An item appears at most once.
    mutating func place(_ item: ChromeItem, in zone: ChromeZone, before target: ChromeItem? = nil) {
        guard zone.allowed.contains(item), item != target else { return }
        for other in ChromeZone.allCases { self[other].removeAll { $0 == item } }
        var items = self[zone]
        let index = target.flatMap { items.firstIndex(of: $0) } ?? items.count
        items.insert(item, at: index)
        self[zone] = items
    }

    mutating func remove(_ item: ChromeItem) {
        for zone in ChromeZone.allCases { self[zone].removeAll { $0 == item } }
    }

    func contains(_ item: ChromeItem) -> Bool {
        ChromeZone.allCases.contains { self[$0].contains(item) }
    }

    /// Items that can still be added.
    func available() -> [ChromeItem] {
        let used = Set(ChromeZone.allCases.flatMap { self[$0] })
        return ChromeItem.allCases.filter { !used.contains($0) }
    }
}
