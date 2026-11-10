import Foundation

/// Browser-facing suggestion endpoints. Fail silently when an engine is unavailable.
enum SearchSuggestions {
    static func endpoint(_ query: String, engine: SearchEngine) -> URL {
        let base: String
        let parameters: [URLQueryItem]
        switch engine {
        case .duckduckgo:
            base = "https://duckduckgo.com/ac/"
            parameters = [.init(name: "type", value: "list"), .init(name: "q", value: query)]
        case .google:
            base = "https://suggestqueries.google.com/complete/search"
            parameters = [.init(name: "client", value: "firefox"), .init(name: "q", value: query)]
        case .bing:
            base = "https://api.bing.com/osjson.aspx"
            parameters = [.init(name: "query", value: query)]
        }
        var url = URLComponents(string: base)!
        url.queryItems = parameters
        return url.url!
    }

    static func parse(_ data: Data, query: String) -> [String] {
        guard data.count <= 65_536, let array = try? JSONSerialization.jsonObject(with: data) as? [Any],
              array.count > 1, let values = array[1] as? [String] else { return [] }
        var seen = Set([query.lowercased()])
        return values.compactMap { value in
            let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, text.count <= 256, seen.insert(text.lowercased()).inserted else { return nil }
            return text
        }.prefix(6).map { $0 }
    }

    static func fetch(_ query: String, engine: SearchEngine) async throws -> [String] {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForRequest = 5
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(from: endpoint(query, engine: engine))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < 65_536 else { return [] }
            data.append(byte)
        }
        return parse(data, query: query)
    }
}
