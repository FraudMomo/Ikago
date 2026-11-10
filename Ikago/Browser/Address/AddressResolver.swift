import Foundation

enum SearchEngine: String, Codable, CaseIterable, Identifiable {
    case duckduckgo, google, bing

    var id: String { rawValue }
    var name: String {
        switch self {
        case .duckduckgo: "DuckDuckGo"
        case .google: "Google"
        case .bing: "Bing"
        }
    }

    func searchURL(_ query: String) -> String {
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? query
        switch self {
        case .duckduckgo: return "https://duckduckgo.com/?q=\(q)"
        case .google: return "https://www.google.com/search?q=\(q)"
        case .bing: return "https://www.bing.com/search?q=\(q)"
        }
    }
}

/// Turns address-bar input into a web or local-file URL, without embedded credentials.
enum AddressResolver {
    enum Failure: Error, LocalizedError {
        case empty, unsupportedScheme, credentials

        var errorDescription: String? {
            switch self {
            case .empty: "Enter an address or search term."
            case .unsupportedScheme: "Use a web address beginning with http or https, or a local file URL."
            case .credentials: "This address contains embedded credentials."
            }
        }
    }

    @MainActor static func resolve(_ input: String, engine: SearchEngine) throws -> String {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw Failure.empty }
        if isLocalFileURL(text), let url = URL(string: text) { return url.absoluteString }

        if text.range(of: #"^(localhost|127\.0\.0\.1|\[::1\])(:\d+)?(/|$)"#,
                      options: [.regularExpression, .caseInsensitive]) != nil {
            return try validated("http://\(text)")
        }
        if let page = InternalPage(url: text) { return page.url }
        if text.range(of: #"^https?://"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return try validated(text)
        }
        if text.range(of: #"^[^\s/:]+\.[^\s/:]+(:\d+)?(/\S*)?$"#, options: .regularExpression) != nil {
            return try validated("https://\(text)")
        }
        if text.range(of: #"^[a-z][a-z\d+.-]*:"#, options: [.regularExpression, .caseInsensitive]) != nil {
            throw Failure.unsupportedScheme
        }
        return engine.searchURL(text)
    }

    /// Network pages only; local files must not enter web history or remote suggestions.
    static func isWebURL(_ string: String) -> Bool {
        guard string.count <= 8192, let c = URLComponents(string: string),
              let scheme = c.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = c.host, !host.isEmpty, c.user == nil, c.password == nil
        else { return false }
        return true
    }

    static func isLocalFileURL(_ string: String) -> Bool {
        guard string.count <= 8192, let url = URL(string: string), url.isFileURL,
              url.user == nil, url.password == nil, url.port == nil,
              url.host == nil || url.host == "" || url.host?.lowercased() == "localhost",
              url.path.hasPrefix("/"), !url.path.hasSuffix("/") else { return false }
        return true
    }

    /// Pages that can be loaded, saved and reopened as browser tabs.
    static func isPageURL(_ string: String) -> Bool {
        isWebURL(string) || isLocalFileURL(string)
    }

    static func hostname(_ url: String) -> String {
        guard let host = URLComponents(string: url)?.host else { return "" }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private static func validated(_ string: String) throws -> String {
        guard let c = URLComponents(string: string), c.host?.isEmpty == false else {
            throw Failure.unsupportedScheme
        }
        if c.user != nil || c.password != nil { throw Failure.credentials }
        return c.url?.absoluteString ?? string
    }
}

private extension CharacterSet {
    static let urlQueryValueAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&+=?#")
        return set
    }()
}
