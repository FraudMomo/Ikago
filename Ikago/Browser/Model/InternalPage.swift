import Foundation

/// Ikago's own pages, shown in a tab like any site: ikago://settings, …
enum InternalPage: String, CaseIterable {
    case settings, history, downloads, bookmarks, welcome, performance, notes, home
    case splitEmpty = "split-empty"

    init?(url: String) {
        guard let c = URLComponents(string: url), c.scheme?.lowercased() == "ikago",
              let host = c.host?.lowercased(), let page = InternalPage(rawValue: host) else { return nil }
        self = page
    }

    var url: String { "ikago://\(rawValue)" }
    var title: String {
        switch self {
        case .splitEmpty: "Empty Split"
        case .home: "New Tab"
        default: rawValue.capitalized
        }
    }

    var symbol: String {
        switch self {
        case .performance: "gauge.with.dots.needle.50percent"
        case .splitEmpty: "rectangle.split.2x1"
        case .bookmarks: "bookmark"
        case .settings: "gearshape"
        case .history: "clock"
        case .downloads: "arrow.down.circle"
        case .notes: "note.text"
        case .welcome: "hand.wave"
        case .home: "house"
        }
    }
}
