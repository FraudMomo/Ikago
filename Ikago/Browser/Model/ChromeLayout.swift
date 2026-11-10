import Foundation

/// A control that can be placed in the top bar or sidebar (Settings ▸ Customize).
enum ChromeItem: String, Codable, CaseIterable, Identifiable {
    case sidebarToggle, back, forward, reload, newTab, spaces, newSpace, history, downloads, settings, bookmarks
    case share, tabOverview

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
        case .share: "Share"
        case .tabOverview: "Tab Overview"
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
        case .share: "square.and.arrow.up"
        case .tabOverview: "square.on.square"
        }
    }
}

/// The places items can go.
enum ChromeZone: String, Codable, CaseIterable {
    case topBarLeading, topBarTrailing, topBarOuterLeading, topBarOuterTrailing, sidebarTop, sidebarBottom

    /// Which bar a zone belongs to; an item appears at most once per bar.
    var isSidebar: Bool { self == .sidebarTop || self == .sidebarBottom }
    var isTopBar: Bool { !isSidebar }

    var allowed: [ChromeItem] { ChromeItem.allCases }
}

/// Which controls show where, in order. Anything not placed is hidden.
struct ChromeLayout: Codable, Equatable {
    var topBarLeading: [ChromeItem] = [.sidebarToggle, .back, .forward]
    var overviewMigrated = true
    var topBarTrailing: [ChromeItem] = [.share, .newTab, .tabOverview]
    var topToolbarMigrated = true
    var topBarOuterLeading: [ChromeItem] = []
    var topBarOuterTrailing: [ChromeItem] = []
    var sidebarTop: [ChromeItem] = [.sidebarToggle, .back, .forward, .reload]
    var sidebarBottom: [ChromeItem] = [.spaces, .newSpace]
    var sidebarShowsAddress = true
    var sidebarShowsNewTab = true

    init() {}

    /// Saved layouts from before a field existed keep working.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ChromeLayout()
        // Skip items this version no longer has, so one retired control can't fail the whole session.
        func items(_ key: CodingKeys) throws -> [ChromeItem]? {
            try c.decodeIfPresent([String].self, forKey: key)?.compactMap(ChromeItem.init(rawValue:))
        }
        topBarLeading = try items(.topBarLeading) ?? d.topBarLeading
        topBarTrailing = try items(.topBarTrailing) ?? d.topBarTrailing
        topBarOuterLeading = try items(.topBarOuterLeading) ?? []
        topBarOuterTrailing = try items(.topBarOuterTrailing) ?? []
        sidebarTop = try items(.sidebarTop) ?? d.sidebarTop
        sidebarBottom = try items(.sidebarBottom) ?? d.sidebarBottom
        sidebarShowsAddress = try c.decodeIfPresent(Bool.self, forKey: .sidebarShowsAddress) ?? true
        sidebarShowsNewTab = try c.decodeIfPresent(Bool.self, forKey: .sidebarShowsNewTab) ?? true
        if try c.decodeIfPresent(Bool.self, forKey: .topToolbarMigrated) != true,
           topBarLeading == d.topBarLeading, topBarTrailing == [.newTab, .spaces],
           topBarOuterLeading.isEmpty, topBarOuterTrailing.isEmpty {
            topBarTrailing = d.topBarTrailing
        }
        if try c.decodeIfPresent(Bool.self, forKey: .overviewMigrated) != true {
            let placed = topBarLeading + topBarTrailing + topBarOuterLeading + topBarOuterTrailing
            if !placed.contains(.sidebarToggle) { topBarLeading.insert(.sidebarToggle, at: 0) }
        }
    }

    subscript(zone: ChromeZone) -> [ChromeItem] {
        get {
            switch zone {
            case .topBarLeading: topBarLeading
            case .topBarTrailing: topBarTrailing
            case .topBarOuterLeading: topBarOuterLeading
            case .topBarOuterTrailing: topBarOuterTrailing
            case .sidebarTop: sidebarTop
            case .sidebarBottom: sidebarBottom
            }
        }
        set {
            switch zone {
            case .topBarLeading: topBarLeading = newValue
            case .topBarTrailing: topBarTrailing = newValue
            case .topBarOuterLeading: topBarOuterLeading = newValue
            case .topBarOuterTrailing: topBarOuterTrailing = newValue
            case .sidebarTop: sidebarTop = newValue
            case .sidebarBottom: sidebarBottom = newValue
            }
        }
    }

    private func zones(sameBarAs zone: ChromeZone) -> [ChromeZone] {
        ChromeZone.allCases.filter { zone.isTopBar ? $0.isTopBar : $0.isSidebar }
    }

    /// Moves (or adds) `item` into `zone` before `target`, or at the end.
    mutating func place(_ item: ChromeItem, in zone: ChromeZone, before target: ChromeItem? = nil) {
        guard zone.allowed.contains(item), item != target else { return }
        for other in zones(sameBarAs: zone) { self[other].removeAll { $0 == item } }
        var items = self[zone]
        let index = target.flatMap { items.firstIndex(of: $0) } ?? items.count
        items.insert(item, at: index)
        self[zone] = items
    }

    mutating func remove(_ item: ChromeItem, fromTopBar: Bool) {
        for zone in ChromeZone.allCases where fromTopBar ? zone.isTopBar : zone.isSidebar { self[zone].removeAll { $0 == item } }
    }

    mutating func remove(_ item: ChromeItem, from zone: ChromeZone) {
        for place in zones(sameBarAs: zone) { self[place].removeAll { $0 == item } }
    }

    func available(in zone: ChromeZone) -> [ChromeItem] {
        let used = Set(zones(sameBarAs: zone).flatMap { self[$0] })
        return zone.allowed.filter { !used.contains($0) }
    }

    func contains(_ item: ChromeItem, inTopBar: Bool) -> Bool {
        ChromeZone.allCases.filter { inTopBar ? $0.isTopBar : $0.isSidebar }.contains { self[$0].contains(item) }
    }

    /// Items that can still be added to a bar.
    func available(topBar: Bool) -> [ChromeItem] {
        let used = Set(ChromeZone.allCases.filter { topBar ? $0.isTopBar : $0.isSidebar }.flatMap { self[$0] })
        let allowed = topBar ? ChromeZone.topBarLeading.allowed : ChromeZone.sidebarTop.allowed
        return allowed.filter { !used.contains($0) }
    }
}
