import Foundation

/// What the address field searches, like Spotlight's filters (⌘1–⌘4): everything, or only open tabs, history, bookmarks
/// or browser actions. A scope shows as a token at the field's start; Esc or ⌫ on an empty field returns to everything.
enum AddressScope: Int, CaseIterable, Identifiable {
    case all, tabs, history, bookmarks, actions
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .all: "All"
        case .tabs: "Tabs"
        case .history: "History"
        case .bookmarks: "Bookmarks"
        case .actions: "Actions"
        }
    }
    var symbol: String {
        switch self {
        case .all: "magnifyingglass"
        case .tabs: "square.on.square"
        case .history: "clock"
        case .bookmarks: "star"
        case .actions: "command"
        }
    }
    /// ⌘1–⌘4; All has none.
    var shortcut: String { self == .all ? "" : "⌘\(rawValue)" }
}

/// A run of results under one heading.
struct AddressSection: Equatable {
    /// Empty for the top hits, which have no heading.
    let title: String
    let range: Range<Int>
    /// The scope that lists more of this kind ("Show More").
    var more: AddressScope? = nil
}

extension CommandPaletteModel {
    /// The most rows a scoped list shows (they scroll); the unscoped list stays at `OmniboxEngine.maxResults`.
    static let scopedLimit = 30

    /// ⌘1–⌘4 pick a scope; the same shortcut again goes back to everything.
    func toggleScope(_ number: Int) -> Bool {
        guard let picked = AddressScope(rawValue: number), picked != .all else { return false }
        scope = scope == picked ? .all : picked
        return true
    }

    /// The results for a scope: every match in the current Space's tabs, history, bookmarks or actions, best first.
    func scopedMatches(_ scope: AddressScope) -> [Suggestion] {
        let terms = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        func matches(_ fields: String...) -> Bool {
            let text = fields.joined(separator: " ").lowercased()
            return terms.allSatisfy { text.contains($0) }
        }
        var out: [Suggestion] = []
        switch scope {
        case .all: return []
        case .tabs:
            for tab in state.spaceTabs where tab.id != state.activeTabID && matches(tab.displayTitle, tab.url) {
                out.append(Suggestion(kind: .open(tab.url), source: .openTab, title: tab.displayTitle,
                                      subtitle: OmniboxURL.display(tab.url), fill: tab.url, relevance: 0, tabID: tab.id))
            }
        case .history:
            var seen = Set<String>()
            for visit in state.history.sorted(by: { $0.time > $1.time }) where matches(visit.title, visit.url) {
                guard seen.insert(OmniboxURL.key(visit.url)).inserted else { continue }
                out.append(Suggestion(kind: .open(visit.url), source: .history, title: visit.title.isEmpty ? OmniboxURL.display(visit.url) : visit.title,
                                      subtitle: OmniboxURL.display(visit.url), fill: visit.url, relevance: 0, removableURL: visit.url))
                if out.count >= Self.scopedLimit { break }
            }
        case .bookmarks:
            for bookmark in state.bookmarks where matches(bookmark.title, bookmark.url) {
                out.append(Suggestion(kind: .open(bookmark.url), source: .bookmark, title: bookmark.title.isEmpty ? OmniboxURL.display(bookmark.url) : bookmark.title,
                                      subtitle: OmniboxURL.display(bookmark.url), fill: bookmark.url, relevance: 0))
            }
        case .actions:
            let split = state.activeTabID.flatMap { state.splitGroup(of: $0) } != nil
            // With nothing typed, the commands; typing also finds settings.
            let actions = (query.trimmingCharacters(in: .whitespaces).isEmpty ? PaletteAction.builtIn : PaletteAction.matching(query))
                .filter { $0.id != (split ? "split" : "unsplit") }
            out = actions.map { Suggestion(kind: .open($0.url), source: .action, title: $0.title,
                                           subtitle: $0.detail.isEmpty ? $0.shortcut : $0.detail, fill: $0.title, relevance: 0) }
        }
        return Array(out.prefix(Self.scopedLimit))
    }

    /// Unscoped results grouped like Spotlight's: the top hit first, then searches, open tabs, pages and actions, each
    /// in its ranked order. The on-focus list keeps searches before pages and has no top hit.
    static func grouped(_ matches: [Suggestion], zeroSuggest: Bool) -> [Suggestion] {
        guard matches.count > 1 else { return matches }
        let head = zeroSuggest ? [] : [matches[0]]
        let rest = zeroSuggest ? matches : Array(matches.dropFirst())
        let order = ["Search", "Open Tabs", "Pages", "Actions"]
        return head + rest.enumerated().sorted { a, b in
            let x = order.firstIndex(of: section(of: a.element)) ?? 0, y = order.firstIndex(of: section(of: b.element)) ?? 0
            return x == y ? a.offset < b.offset : x < y
        }.map(\.element)
    }

    static func section(of match: Suggestion) -> String {
        if match.source == .action { return "Actions" }
        if match.isSearch { return "Search" }
        if match.tabID != nil { return "Open Tabs" }
        return "Pages"
    }

    /// Headings for the rows as they are listed.
    var sections: [AddressSection] {
        let items = suggestions
        guard !items.isEmpty else { return [] }
        func title(_ match: Suggestion) -> String {
            switch scope {
            case .tabs: return "Open Tabs"
            case .history: return "History"
            case .bookmarks: return "Bookmarks"
            case .actions: return "Actions"
            case .all:
                let name = Self.section(of: match)
                if isZeroSuggest { return name == "Search" ? "Recent Searches" : name == "Pages" ? "Frequently Visited" : name }
                return name == "Search" ? "Suggestions" : name
            }
        }
        var out: [AddressSection] = []
        var start = 0
        let topHit = scope == .all && !isZeroSuggest
        if topHit { out.append(AddressSection(title: "", range: 0..<1)); start = 1 }
        var index = start
        while index < items.count {
            let name = title(items[index])
            var end = index + 1
            while end < items.count, title(items[end]) == name { end += 1 }
            let more: AddressScope? = scope != .all ? nil
                : name == "Open Tabs" ? .tabs : name == "Pages" || name == "Frequently Visited" ? .history : name == "Actions" ? .actions : nil
            out.append(AddressSection(title: name, range: index..<end, more: more))
            index = end
        }
        return out
    }
}
