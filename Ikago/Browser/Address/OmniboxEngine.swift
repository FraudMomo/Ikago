import Foundation

/// One omnibox result. Relevance follows Chromium's scale: inline-autocompleted navigation
/// (1400+) beats search-what-you-typed (1300), which beats previous and suggested searches
/// (1200s) and ordinary history/bookmark matches (≤ 1199).
struct OmniboxMatch: Identifiable, Equatable {
    enum Kind: Hashable { case open(String), search(String) }
    enum Source: Equatable { case whatYouTyped, history, bookmark, openTab, searchHistory, suggestion }

    var id: Kind { kind }
    let kind: Kind
    let source: Source
    /// Search rows: the query. Navigation rows: the page title (or its address).
    let title: String
    /// Search rows: "Search Google" for what-you-typed. Navigation rows: the address without scheme.
    let subtitle: String
    /// Text the field shows while this row is highlighted with the arrow keys.
    let fill: String
    var relevance: Int
    /// The default match's inline completion: the untyped remainder, shown selected in the field.
    var inline = ""
    /// Another tab already shows this page ("Switch to this tab").
    var tabID: String?
    /// History rows can be deleted from the dropdown (Shift+Delete or ×).
    var removableURL: String?

    var symbol: String {
        switch source {
        case .whatYouTyped, .suggestion: isSearch ? "magnifyingglass" : "globe"
        case .searchHistory: "clock.arrow.circlepath"
        case .history: "clock"
        case .bookmark: "star"
        case .openTab: "square.on.square"
        }
    }
    var isSearch: Bool { if case .search = kind { true } else { false } }
    var url: String { switch kind { case .open(let url), .search(let url): url } }
}

@MainActor
struct OmniboxEngine {
    let state: BrowserState
    static let maxResults = 8

    func matches(for input: OmniboxInput, remote: [String], zeroSuggest: Bool) -> [OmniboxMatch] {
        if input.text.isEmpty || zeroSuggest { return onFocus() }
        var results = whatYouTyped(input) + searchHistory(input) + suggestions(input, remote: remote)
        let (pages, best) = navigation(input)
        if let best { results.append(best) }
        results += pages
        // Highest relevance wins; one row per destination, the default first, then at most eight.
        // A dropped duplicate still lends its open tab and removability to the row that won.
        var seen: [String: Int] = [:], out: [OmniboxMatch] = []
        for match in results.enumerated().sorted(by: { $0.element.relevance == $1.element.relevance
            ? $0.offset < $1.offset : $0.element.relevance > $1.element.relevance }).map(\.element) {
            let key = match.isSearch ? "search:" + match.title.lowercased() : OmniboxURL.key(match.url)
            if let index = seen[key] {
                if index < out.count {
                    out[index].tabID = out[index].tabID ?? match.tabID
                    out[index].removableURL = out[index].removableURL ?? match.removableURL
                }
                continue
            }
            seen[key] = out.count < Self.maxResults ? out.count : Int.max
            if out.count < Self.maxResults { out.append(match) }
        }
        if !out.isEmpty, out[0].inline.isEmpty == false, !input.allowsInline { out[0].inline = "" }
        for index in out.indices.dropFirst() { out[index].inline = "" }
        return out
    }

    private func whatYouTyped(_ input: OmniboxInput) -> [OmniboxMatch] {
        let engine = state.searchEngine
        var out = [OmniboxMatch(kind: .search(engine.searchURL(input.text)), source: .whatYouTyped, title: input.text,
                                subtitle: "\(engine.name) Search", fill: input.text, relevance: input.kind == .url ? 1150 : 1300)]
        if input.kind == .url, let url = try? AddressResolver.resolve(input.text, engine: engine) {
            out.append(OmniboxMatch(kind: .open(url), source: .whatYouTyped, title: OmniboxURL.display(url),
                                    subtitle: "", fill: input.text, relevance: 1200))
        }
        return out
    }

    /// Earlier searches from history, shown as search rows.
    private func searchHistory(_ input: OmniboxInput) -> [OmniboxMatch] {
        guard state.searchShowsHistory, input.kind != .url else { return [] }
        let needle = input.text.lowercased()
        var best: [String: (String, Double)] = [:]
        for visit in state.history {
            guard let terms = OmniboxURL.searchTerms(visit.url), terms.lowercased() != needle,
                  terms.lowercased().hasPrefix(needle) || OmniboxURL.words(terms).contains(where: { $0.hasPrefix(needle) }) else { continue }
            let score = OmniboxScore.frecency(visits: visit.visits ?? 1, typed: visit.typed ?? 0, time: visit.time)
            if score > best[terms.lowercased()]?.1 ?? -1 { best[terms.lowercased()] = (terms, score) }
        }
        return best.values.sorted { $0.1 > $1.1 }.prefix(3).map { terms, score in
            OmniboxMatch(kind: .search(state.searchEngine.searchURL(terms)), source: .searchHistory, title: terms,
                         subtitle: "", fill: terms, relevance: 1240 + Int(39 * score))
        }
    }

    private func suggestions(_ input: OmniboxInput, remote: [String]) -> [OmniboxMatch] {
        remote.prefix(5).enumerated().map { index, text in
            OmniboxMatch(kind: .search(state.searchEngine.searchURL(text)), source: .suggestion, title: text,
                         subtitle: "", fill: text, relevance: 1230 - index)
        }
    }

    private struct Page {
        var url: String, title: String, visits = 0, typed = 0, time: UInt64 = 0
        var bookmarked = false, inHistory = false, tabID: String?, favicon: String?
        var frecency: Double {
            let base = inHistory ? OmniboxScore.frecency(visits: visits, typed: typed, time: time) : 0.4
            return min(1, base + (bookmarked ? 0.2 : 0))
        }
        /// Chromium only inline-autocompletes pages the user has typed or visited repeatedly.
        var inlineable: Bool { typed > 0 || visits >= 3 || bookmarked }
    }

    /// History, bookmarks and open tabs merged per page, plus the best inline-autocompletion.
    private func navigation(_ input: OmniboxInput) -> ([OmniboxMatch], OmniboxMatch?) {
        var pages: [String: Page] = [:]
        if state.searchShowsHistory {
            for visit in state.history where OmniboxURL.searchTerms(visit.url) == nil {
                let key = OmniboxURL.key(visit.url)
                var page = pages[key] ?? Page(url: visit.url, title: visit.title)
                page.inHistory = true
                page.visits += visit.visits ?? 1; page.typed += visit.typed ?? 0; page.time = max(page.time, visit.time)
                pages[key] = page
            }
        }
        for bookmark in state.bookmarks {
            let key = OmniboxURL.key(bookmark.url)
            var page = pages[key] ?? Page(url: bookmark.url, title: bookmark.title)
            page.bookmarked = true
            if page.title.isEmpty { page.title = bookmark.title }
            pages[key] = page
        }
        let switching = state.browserPreferences.showSwitchToTabSuggestions ?? true
        for tab in state.tabs where tab.id != state.activeTabID && tab.spaceID == state.activeSpaceID && AddressResolver.isWebURL(tab.url) {
            let key = OmniboxURL.key(tab.url)
            var page = pages[key] ?? Page(url: tab.url, title: tab.displayTitle)
            if switching { page.tabID = page.tabID ?? tab.id }
            if page.title.isEmpty { page.title = tab.displayTitle }
            pages[key] = page
        }

        var matches: [OmniboxMatch] = []
        var hosts: [String: (page: Page, score: Double)] = [:]
        for page in pages.values {
            let topicality = OmniboxScore.topicality(terms: input.terms, stripped: input.stripped, title: page.title, url: page.url)
            guard topicality > 0 else { continue }
            let stripped = OmniboxURL.strip(page.url)
            if page.inlineable, !input.stripped.isEmpty, stripped.hasPrefix(input.stripped) {
                let host = OmniboxURL.host(stripped)
                let target = input.stripped.count <= host.count ? host : stripped
                if page.frecency > hosts[target]?.score ?? -1 { hosts[target] = (page, page.frecency) }
            }
            matches.append(match(for: page, relevance: 900 + Int(299 * topicality * page.frecency)))
        }
        guard let (target, best) = hosts.max(by: { $0.value.score < $1.value.score }).map({ ($0.key, $0.value.page) }) else {
            return (matches, nil)
        }
        // Completing within the host lands on the host root, as Chrome does for "git" → github.com.
        let isHost = !target.contains("/")
        let destination = isHost ? (OmniboxURL.root(best.url) ?? best.url) : best.url
        var top = match(for: best, url: destination, title: isHost ? (pages[target]?.title ?? target) : best.title)
        top.relevance = input.allowsInline ? 1410 + Int(3 * best.frecency) : 1100 + Int(99 * best.frecency)
        top.inline = String(target.dropFirst(min(target.count, input.stripped.count)))
        return (matches, top)
    }

    private func match(for page: Page, url: String? = nil, title: String? = nil, relevance: Int = 0) -> OmniboxMatch {
        let url = url ?? page.url, title = (title ?? page.title).isEmpty ? OmniboxURL.display(url) : (title ?? page.title)
        let source: OmniboxMatch.Source = page.inHistory ? .history : page.bookmarked ? .bookmark : .openTab
        return OmniboxMatch(kind: .open(url), source: source, title: title, subtitle: OmniboxURL.display(url),
                            fill: OmniboxURL.display(url), relevance: relevance, tabID: page.tabID, removableURL: page.inHistory ? page.url : nil)
    }

    /// Focusing the field (empty, or the untouched page address): recent searches first, as in
    /// recent searches, then most visited pages. The current page is left out.
    private func onFocus() -> [OmniboxMatch] {
        guard state.searchShowsHistory else { return [] }
        var seen = Set<String>(), searches: [OmniboxMatch] = []
        for visit in state.history.sorted(by: { $0.time > $1.time }) {
            guard searches.count < 5, let terms = OmniboxURL.searchTerms(visit.url), seen.insert(terms.lowercased()).inserted else { continue }
            searches.append(OmniboxMatch(kind: .search(state.searchEngine.searchURL(terms)), source: .searchHistory, title: terms,
                                         subtitle: "", fill: terms, relevance: 1300, removableURL: visit.url))
        }
        let current = state.activeTab.map { OmniboxURL.key($0.url) }
        let pages = mostVisited().filter { OmniboxURL.key($0.url) != current }
        return Array((searches + pages).prefix(Self.maxResults))
    }

    /// Most visited pages by frecency.
    private func mostVisited() -> [OmniboxMatch] {
        guard state.searchShowsHistory else { return [] }
        var seen = Set<String>()
        return state.history.filter { OmniboxURL.searchTerms($0.url) == nil && seen.insert(OmniboxURL.key($0.url)).inserted }
            .map { ($0, OmniboxScore.frecency(visits: $0.visits ?? 1, typed: $0.typed ?? 0, time: $0.time)) }
            .sorted { $0.1 > $1.1 }.prefix(6)
            .map { visit, score in
                let tab = state.tabs.first { $0.id != state.activeTabID && $0.spaceID == state.activeSpaceID && OmniboxURL.key($0.url) == OmniboxURL.key(visit.url) }
                return OmniboxMatch(kind: .open(visit.url), source: .history, title: visit.title.isEmpty ? OmniboxURL.display(visit.url) : visit.title,
                                    subtitle: OmniboxURL.display(visit.url), fill: OmniboxURL.display(visit.url), relevance: 900 + Int(299 * score),
                                    tabID: (state.browserPreferences.showSwitchToTabSuggestions ?? true) ? tab?.id : nil, removableURL: visit.url)
            }
    }
}
