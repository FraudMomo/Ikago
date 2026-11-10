import Foundation

/// What the user typed, classified the way Chromium's AutocompleteInput does.
struct OmniboxInput {
    enum Kind { case url, query, unknown }

    let text: String
    let kind: Kind
    /// Lowercased, with any scheme and leading "www." removed, for URL prefix matching.
    let stripped: String
    /// Lowercased words for history and bookmark matching.
    let terms: [String]
    /// Inline autocompletion is allowed only while typing forward (never after a deletion or paste).
    let allowsInline: Bool

    @MainActor init(_ raw: String, engine: SearchEngine, allowsInline: Bool) {
        text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()
        stripped = OmniboxURL.strip(lower)
        terms = lower.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        if AddressResolver.isLocalFileURL(text) {
            kind = .url
        } else if text.hasPrefix("?") || text.contains(" ") && !text.lowercased().hasPrefix("http") {
            kind = .query
        } else if let url = try? AddressResolver.resolve(text, engine: engine), url != engine.searchURL(text) {
            kind = .url
        } else {
            kind = .unknown
        }
        self.allowsInline = allowsInline && kind != .query && !text.isEmpty && !text.hasSuffix(" ")
    }
}

enum OmniboxURL {
    /// "https://www.GitHub.com/" → "github.com"; paths and queries are kept.
    static func strip(_ value: String) -> String {
        var s = value.lowercased()
        for scheme in ["https://", "http://"] where s.hasPrefix(scheme) { s.removeFirst(scheme.count) }
        if s.hasPrefix("www.") { s.removeFirst(4) }
        if let hash = s.firstIndex(of: "#") { s = String(s[..<hash]) }
        if s.hasSuffix("/"), s.filter({ $0 == "/" }).count == 1 { s.removeLast() }
        return s
    }

    /// Display form: no "https://" or "www.", no root slash; case and path preserved.
    static func display(_ url: String) -> String {
        var s = url
        for scheme in ["https://", "http://"] where s.lowercased().hasPrefix(scheme) { s.removeFirst(scheme.count) }
        // user:password@ can make a link read as another site, and shouldn't be shown anyway.
        let authority = s.prefix { $0 != "/" && $0 != "?" && $0 != "#" }
        if let at = authority.lastIndex(of: "@") { s.removeSubrange(s.startIndex...at) }
        if s.lowercased().hasPrefix("www.") { s.removeFirst(4) }
        if s.hasSuffix("/"), s.filter({ $0 == "/" }).count == 1 { s.removeLast() }
        return s
    }

    /// One candidate per page, regardless of scheme, "www." or a trailing root slash.
    static func key(_ url: String) -> String { strip(url) }

    /// The host root of `url`, keeping its scheme and "www." so navigation lands where history did.
    static func root(_ url: String) -> String? {
        guard var parts = URLComponents(string: url), parts.host != nil else { return nil }
        parts.path = "/"; parts.query = nil; parts.fragment = nil
        return parts.url?.absoluteString
    }

    static func host(_ stripped: String) -> String {
        String(stripped.prefix { $0 != "/" && $0 != "?" && $0 != "#" })
    }

    /// Words of a URL or title: runs of letters and digits.
    static func words(_ text: String) -> [Substring] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }
    }

    /// Search terms if `url` is a results page of any built-in engine.
    static func searchTerms(_ url: String) -> String? {
        guard let parts = URLComponents(string: url), let host = parts.host?.lowercased() else { return nil }
        let isSearch = (host.hasSuffix("google.com") && parts.path == "/search")
            || (host.hasSuffix("bing.com") && parts.path == "/search")
            || (host.hasSuffix("duckduckgo.com") && (parts.path == "/" || parts.path.isEmpty))
        guard isSearch, let q = parts.queryItems?.first(where: { $0.name == "q" })?.value?
            .replacingOccurrences(of: "+", with: " ").trimmingCharacters(in: .whitespacesAndNewlines),
              !q.isEmpty, q.count <= 256 else { return nil }
        return q
    }
}

/// Chromium-like ranking signals: how well the input matches, and how often/recently a page was used.
enum OmniboxScore {
    /// 0…1. Every term must match; URL host prefixes beat word prefixes beat substrings.
    static func topicality(terms: [String], stripped input: String, title: String, url: String) -> Double {
        guard !terms.isEmpty else { return 0 }
        let page = OmniboxURL.strip(url), host = OmniboxURL.host(page)
        if !input.isEmpty, !input.contains(" "), page.hasPrefix(input) { return host.count >= input.count ? 1 : 0.95 }
        let urlWords = OmniboxURL.words(page), titleWords = OmniboxURL.words(title)
        let lowerTitle = title.lowercased()
        var total = 0.0
        for term in terms {
            let word = OmniboxURL.words(term).first.map(String.init) ?? term
            if urlWords.contains(where: { $0.hasPrefix(word) }) && host.contains(word) { total += 0.85 }
            else if titleWords.contains(where: { $0.hasPrefix(word) }) { total += 0.75 }
            else if urlWords.contains(where: { $0.hasPrefix(word) }) { total += 0.65 }
            else if term.count >= 3, page.contains(term) { total += 0.45 }
            else if term.count >= 3, lowerTitle.contains(term) { total += 0.4 }
            else { return 0 }
        }
        return total / Double(terms.count)
    }

    /// 0…1 from visit and typed counts (typed visits weigh more) and Chromium's recency buckets.
    static func frecency(visits: Int, typed: Int, time: UInt64, now: Date = Date()) -> Double {
        let days = max(0, now.timeIntervalSince1970 - Double(time) / 1000) / 86_400
        let recency: Double = days < 4 ? 1 : days < 14 ? 0.7 : days < 31 ? 0.5 : days < 90 ? 0.3 : 0.1
        let frequency = 1 - exp(-Double(max(1, visits) + typed * 5) / 8)
        return 0.5 * recency + 0.5 * frequency
    }
}
