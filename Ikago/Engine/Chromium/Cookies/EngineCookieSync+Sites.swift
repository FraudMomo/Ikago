import Foundation

/// Site rules (`SiteEngines`): a site that changes engine takes its logins along. Only that site's cookies are copied
/// (its own, its subdomains' and its parent domains'), from the engine it used to the one it uses now, and nothing is
/// deleted. Both stores are reachable only while Chromium runs, so a move waits for such a launch.
extension EngineCookieSync {
    private struct Move: Codable, Equatable { let site: String; let to: String }
    private static let movesKey = "SiteEngineLoginMoves"

    private static var pendingMoves: [Move] {
        get { UserDefaults.standard.data(forKey: movesKey).flatMap { try? JSONDecoder().decode([Move].self, from: $0) } ?? [] }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: movesKey) }
    }

    /// Whether a rule (not the default engine) keeps this cookie domain's site on `engine`.
    static func ruled(domain: String, to engine: BrowserEngine, preferences: BrowserPreferences) -> Bool {
        let host = (domain.hasPrefix(".") ? String(domain.dropFirst()) : domain).lowercased()
        return SiteEngines.rule(forHost: host, preferences: preferences) == engine
    }

    /// Whether a cookie for `domain` is sent to `site` or one of its subdomains.
    static func cookie(domain: String, appliesTo site: String) -> Bool {
        let host = (domain.hasPrefix(".") ? String(domain.dropFirst()) : domain).lowercased()
        guard !host.isEmpty else { return false }
        return host == site || site.hasSuffix("." + host) || host.hasSuffix("." + site)
    }

    /// The person changed site rules: queue the sites that now use another engine, and move them now if possible.
    static func rulesChanged(from old: BrowserPreferences, to new: BrowserPreferences, profiles: Set<String>) async {
        guard usesRealStores else { return }
        let changed = SiteEngines.changedSites(from: old, to: new)
        guard !changed.isEmpty else { return }
        let sites = Set(changed.map(\.site))
        pendingMoves = pendingMoves.filter { !sites.contains($0.site) } + changed.map { Move(site: $0.site, to: $0.to.rawValue) }
        await moveSiteLogins(profiles: profiles)
    }

    /// Copies queued sites' cookies into the engine each now uses. At launch, before any tab, and after rule changes.
    static func moveSiteLogins(profiles: Set<String>) async {
        guard usesRealStores, BrowserRuntime.runs(.chromium) else { return }
        let moves = pendingMoves
        guard !moves.isEmpty else { return }
        var done: [Move] = []
        var wroteWebKit = false
        for move in moves {
            guard let target = BrowserEngine(rawValue: move.to) else { done.append(move); continue }
            var moved = true
            for profile in profiles.sorted() {
                do {
                    try CEFSessions.prepare(profile)
                    let store = WebProfiles.dataStore(for: profile).httpCookieStore
                    let matches: (String) -> Bool = { cookie(domain: $0, appliesTo: move.site) }
                    if target == .chromium {
                        _ = try await copyToChromium(from: store, profile: profile, mirror: false, including: matches)
                    } else {
                        _ = try await copyToWebKit(profile: profile, store: store, mirror: false, including: matches)
                        wroteWebKit = true
                    }
                } catch {
                    moved = false
                    NSLog("Ikago: couldn't move a site's sign-in to its engine: %@", error.localizedDescription)
                }
            }
            if moved { done.append(move) }
        }
        // Rules may have changed again meanwhile: drop only what was moved.
        pendingMoves = pendingMoves.filter { !done.contains($0) }
        if wroteWebKit { await withCheckedContinuation { finished in WebProfiles.flushCookies(evenOnChromium: true) { finished.resume() } } }
    }
}
