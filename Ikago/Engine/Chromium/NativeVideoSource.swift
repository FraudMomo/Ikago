import Foundation

/// Where macOS's player gets a video Chromium can't play. A page's own HTTPS file is used as is. On X,
/// the tweet's streams come from X's public embed endpoint (what embedded tweets use), without cookies,
/// and only streams on video.twimg.com are accepted.
@MainActor
enum NativeVideoSource {
    struct Request: Equatable {
        var kind: String, src: String?, status: String?, token: String?, thumb: String?, media: String?
    }

    struct Stream: Equatable {
        let url: URL
        /// An X "GIF": loops silently without controls.
        let isGIF: Bool
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 15
        return URLSession(configuration: configuration)
    }()

    /// Tweet ID → its media (thumbnail path → stream), so a timeline asks once per tweet.
    private static var tweets: [String: [String: Stream]] = [:]
    private static var pending: [String: Task<[String: Stream], Never>] = [:]

    static func stream(for request: Request) async -> Stream? {
        switch request.kind {
        case "direct":
            guard let src = request.src, let url = URL(string: src), url.scheme == "https", url.host != nil,
                  url.user == nil, url.password == nil else { return nil }
            return Stream(url: url, isGIF: false)
        case "x":
            guard let status = request.status, status.count <= 25, status.allSatisfy({ ("0"..."9").contains($0) }),
                  let thumb = request.thumb, let mediaID = request.media else { return nil }
            let token = request.token.flatMap { $0.allSatisfy { ("0"..."9").contains($0) || ("a"..."z").contains($0) } ? $0 : nil } ?? "a"
            let found = await streams(for: status, token: token)
            return found["/\(thumb)/\(mediaID)"]
        default:
            return nil
        }
    }

    private static func streams(for status: String, token: String) async -> [String: Stream] {
        if let cached = tweets[status] { return cached }
        if let running = pending[status] { return await running.value }
        let task = Task { await fetch(status, token: token) }
        pending[status] = task
        let result = await task.value
        pending[status] = nil
        tweets[status] = result
        if tweets.count > 300 { tweets.removeAll() }
        return result
    }

    private static func fetch(_ status: String, token: String) async -> [String: Stream] {
        var components = URLComponents(string: "https://cdn.syndication.twimg.com/tweet-result")!
        components.queryItems = [.init(name: "id", value: status), .init(name: "lang", value: "en"), .init(name: "token", value: token)]
        guard let url = components.url, let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let tweet = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        var result: [String: Stream] = [:]
        for source in [tweet, tweet["quoted_tweet"] as? [String: Any], tweet["parent"] as? [String: Any]].compactMap({ $0 }) {
            for media in source["mediaDetails"] as? [[String: Any]] ?? [] {
                guard let thumbnail = (media["media_url_https"] as? String).flatMap(URL.init(string:)),
                      let info = media["video_info"] as? [String: Any],
                      let variants = info["variants"] as? [[String: Any]] else { continue }
                let isGIF = media["type"] as? String == "animated_gif"
                // Thumbnail path "/ext_tw_video_thumb/<media>/…" → "/ext_tw_video_thumb/<media>".
                let parts = thumbnail.path.split(separator: "/")
                guard parts.count >= 2 else { continue }
                let key = "/\(parts[0])/\(parts[1])"
                if let stream = bestStream(variants, isGIF: isGIF) { result[key] = stream }
            }
        }
        return result
    }

    /// HLS adapts to the connection; GIFs only come as MP4.
    private static func bestStream(_ variants: [[String: Any]], isGIF: Bool) -> Stream? {
        func url(_ variant: [String: Any]) -> URL? {
            guard let text = (variant["url"] ?? variant["src"]) as? String, let url = URL(string: text),
                  url.scheme == "https", url.host == "video.twimg.com" else { return nil }
            return url
        }
        if !isGIF, let hls = variants.first(where: { ($0["content_type"] as? String)?.lowercased() == "application/x-mpegurl" }),
           let hlsURL = url(hls) {
            return Stream(url: hlsURL, isGIF: false)
        }
        let mp4 = variants.filter { $0["content_type"] as? String == "video/mp4" }
            .max { Int("\($0["bitrate"] ?? 0)") ?? 0 < Int("\($1["bitrate"] ?? 0)") ?? 0 }
        return mp4.flatMap(url).map { Stream(url: $0, isGIF: isGIF) }
    }
}
