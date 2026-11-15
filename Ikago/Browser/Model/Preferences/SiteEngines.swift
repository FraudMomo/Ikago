import Foundation

/// Which engine opens which site. Everything without a rule uses the default engine (Settings ▸ Engine). Ready-made
/// lists (`SiteEngineList`) can be assigned to an engine as a whole; the person's own sites win over them. A rule for a
/// host covers its subdomains, and the most specific rule wins (music.apple.com over apple.com).
@MainActor
enum SiteEngines {
    /// The engine for a page at `url` in a window with these preferences, limited to the engines running in this launch.
    static func engine(for url: String, preferences: BrowserPreferences, isPrivate: Bool) -> BrowserEngine {
        let fallback = BrowserRuntime.engine
        guard !isPrivate, let chosen = rule(for: url, preferences: preferences) else { return fallback }
        return BrowserRuntime.runs(chosen) ? chosen : fallback
    }

    /// The engine a rule assigns to `url`, if any, whether or not that engine is running.
    static func rule(for url: String, preferences: BrowserPreferences) -> BrowserEngine? {
        guard let parsed = URL(string: url), ["http", "https"].contains(parsed.scheme?.lowercased() ?? ""),
              let host = parsed.host?.lowercased() else { return nil }
        return rule(forHost: host, preferences: preferences)
    }

    static func rule(forHost host: String, preferences: BrowserPreferences) -> BrowserEngine? {
        var best: (length: Int, own: Bool, engine: BrowserEngine)?
        func consider(_ site: String, _ engine: BrowserEngine, own: Bool) {
            guard host == site || host.hasSuffix("." + site) else { return }
            if let best, best.length > site.count || (best.length == site.count && best.own) { return }
            best = (site.count, own, engine)
        }
        for list in SiteEngineList.all {
            guard let engine = preferences.siteEngineLists?[list.id].flatMap(BrowserEngine.init(rawValue:)) else { continue }
            for site in list.sites { consider(site, engine, own: false) }
        }
        for (site, raw) in preferences.siteEngines ?? [:] {
            if let engine = BrowserEngine(rawValue: raw) { consider(site, engine, own: true) }
        }
        return best?.engine
    }

    /// "https://www.Example.com/path" or "example.com" → "example.com"; nil when it isn't a host name.
    static func normalizedSite(_ text: String) -> String? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !value.contains("://") { value = "https://" + value }
        guard var host = URL(string: value)?.host, host.contains("."), !host.hasPrefix("."), !host.hasSuffix("."),
              host.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }) else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }

    /// The engines a launch with these preferences needs: the default, plus any engine a rule assigns.
    static func engines(for preferences: BrowserPreferences) -> Set<BrowserEngine> {
        var engines: Set<BrowserEngine> = [preferences.preferredEngine]
        engines.formUnion((preferences.siteEngines ?? [:]).values.compactMap(BrowserEngine.init(rawValue:)))
        engines.formUnion((preferences.siteEngineLists ?? [:]).values.compactMap(BrowserEngine.init(rawValue:)))
        return engines
    }

    /// Sites whose engine differs between two sets of preferences (same default engine): their logins should move.
    static func changedSites(from old: BrowserPreferences, to new: BrowserPreferences) -> [(site: String, from: BrowserEngine, to: BrowserEngine)] {
        var sites = Set((old.siteEngines ?? [:]).keys).union((new.siteEngines ?? [:]).keys)
        for list in SiteEngineList.all where old.siteEngineLists?[list.id] != new.siteEngineLists?[list.id] { sites.formUnion(list.sites) }
        return sites.sorted().compactMap { site in
            let before = rule(forHost: site, preferences: old) ?? old.preferredEngine
            let after = rule(forHost: site, preferences: new) ?? new.preferredEngine
            return before == after ? nil : (site, before, after)
        }
    }
}

/// A ready-made list of sites that work best on one engine, which the person assigns as a whole.
struct SiteEngineList: Identifiable, Sendable {
    let id: String
    let title: String
    let symbol: String
    /// Which engine suits these sites, and why; shown as a hint, never applied by itself.
    let suggested: BrowserEngine
    let reason: String
    let sites: [String]

    static let all: [SiteEngineList] = [
        SiteEngineList(id: "social", title: "Social", symbol: "bubble.left.and.bubble.right", suggested: .webkit,
                       reason: "Their videos use H.264, which Chromium here can’t play.",
                       sites: ["x.com", "twitter.com", "instagram.com", "facebook.com", "threads.com", "threads.net", "tiktok.com",
                               "linkedin.com", "reddit.com", "bsky.app", "pinterest.com", "tumblr.com", "snapchat.com", "mastodon.social"]),
        SiteEngineList(id: "video", title: "Movies & TV", symbol: "film", suggested: .webkit,
                       reason: "Protected video (FairPlay) plays only in WebKit.",
                       sites: ["netflix.com", "primevideo.com", "disneyplus.com", "max.com", "hbomax.com", "hulu.com", "tv.apple.com",
                               "paramountplus.com", "peacocktv.com", "crunchyroll.com", "twitch.tv", "vimeo.com", "dailymotion.com",
                               "plex.tv", "mubi.com", "dazn.com", "skyshowtime.com", "viaplay.com"]),
        SiteEngineList(id: "music", title: "Music", symbol: "music.note", suggested: .webkit,
                       reason: "Streaming services protect their audio, which needs WebKit.",
                       sites: ["spotify.com", "music.apple.com", "tidal.com", "deezer.com", "soundcloud.com", "music.amazon.com",
                               "pandora.com", "bandcamp.com"]),
        SiteEngineList(id: "calls", title: "Video Calls", symbol: "video", suggested: .chromium,
                       reason: "Call sites test against Chrome first.",
                       sites: ["meet.google.com", "zoom.us", "teams.microsoft.com", "teams.live.com", "whereby.com", "discord.com",
                               "webex.com", "around.co", "slack.com"]),
        SiteEngineList(id: "google", title: "Google", symbol: "globe", suggested: .chromium,
                       reason: "Google builds its apps for Chrome first.",
                       sites: ["google.com", "youtube.com", "gmail.com", "googleusercontent.com", "gstatic.com"]),
        SiteEngineList(id: "shopping", title: "Shopping & Banking", symbol: "creditcard", suggested: .webkit,
                       reason: "Apple Passwords and passkeys fill here.",
                       sites: ["amazon.com", "ebay.com", "etsy.com", "paypal.com", "apple.com", "shopify.com", "stripe.com", "klarna.com"]),
    ]
}
