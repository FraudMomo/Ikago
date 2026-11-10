import AppKit

/// Per-site engines in a real hidden window: a Chromium tab that follows a link to a site assigned to WebKit reopens it
/// there, Back and Forward cross the switch, an address typed into the WebKit tab returns to Chromium, and the rule
/// logic itself (lists, own sites, specificity, login moves). WebKit stores are disposable in check runs.
@MainActor
enum CEFSiteEngineChecks {
    static func run(url: String) async throws {
        try rules()
        guard let fixture = URL(string: url), let port = fixture.port else { throw CEFError.script("No fixture address.") }
        let chromiumURL = "http://localhost:\(port)/"   // no rule: the default engine
        let webkitURL = "http://127.0.0.1:\(port)/"     // ruled to WebKit below
        let previous = BrowserRuntime.running
        BrowserRuntime.running = [.chromium, .webkit]
        defer { BrowserRuntime.running = previous }
        let state = BrowserState()
        for tab in Array(state.tabs) { state.closeTab(tab.id) }
        state.browserPreferences.siteEngines = ["127.0.0.1": BrowserEngine.webkit.rawValue]
        let tab = state.newTab(url: chromiumURL)!
        let shell = BrowserWindowController(state: state)
        defer { state.freezeForShutdown(); shell.content.shutdown() }
        try await wait { (shell.activeController?.page as? CEFWebTab)?.isLoading == false && shell.activeController?.page?.currentURL == chromiumURL }
        guard let original = shell.activeController?.page, tab.engine == .chromium else { throw CEFError.script("The tab didn't open in Chromium.") }

        // A page-initiated navigation to the WebKit site hands off.
        // The navigation it starts can cut the script's own reply short.
        _ = try? await original.evaluate("setTimeout(() => { location.href = '\(webkitURL)' }, 0); true")
        try await wait { shell.activeController?.page is WebKitTab }
        guard let controller = shell.activeController, let badge = controller.engineBadge, badge.superview === controller.hostView,
              badge.window === shell.window, controller.hostView.bounds.contains(badge.frame), badge.frame.width > 40 else {
            throw CEFError.script("The engine badge didn't appear inside the page.")
        }
        try await wait { shell.activeController?.page?.currentURL == webkitURL && shell.activeController?.page?.isLoading == false }
        guard tab.engine == .webkit, tab.canGoBack else {
            throw CEFError.script("The WebKit site didn't reopen in WebKit with Back available and the engine badge shown.")
        }
        guard try await shell.activeController?.page?.evaluate("document.title") as? String == "Ikago Chromium Fixture" else {
            throw CEFError.script("The handed-off page didn't load in WebKit.")
        }

        // Back returns to the very Chromium page that was left, and Forward to the WebKit one.
        shell.goBack()
        try await wait { shell.activeController?.page === original }
        guard tab.engine == .chromium, tab.canGoForward else { throw CEFError.script("Back didn't return to the Chromium page.") }
        shell.goForward()
        try await wait { shell.activeController?.page is WebKitTab }

        // An address opened in the WebKit tab for a site without a rule goes back to Chromium.
        shell.activeController?.load(chromiumURL)
        try await wait { (shell.activeController?.page as? CEFWebTab)?.currentURL == chromiumURL }
        guard tab.engine == .chromium else { throw CEFError.script("The unruled site didn't return to Chromium.") }
        print("CEF_SITE_ENGINES_OK handoff back forward typed-address badge")
    }

    /// The rule logic, without pages.
    private static func rules() throws {
        var preferences = BrowserPreferences()
        preferences.browserEngine = BrowserEngine.chromium.rawValue
        preferences.siteEngineLists = ["social": "webkit", "shopping": "webkit"]
        preferences.siteEngines = ["tv.apple.com": "chromium", "mobile.x.com": "chromium"]
        func engine(_ host: String) -> BrowserEngine? { SiteEngines.rule(forHost: host, preferences: preferences) }
        guard engine("x.com") == .webkit, engine("www.x.com") == .webkit, engine("notx.com") == nil, engine("x.com.evil.test") == nil else {
            throw CEFError.script("A list didn't cover its sites and only those.")
        }
        guard engine("apple.com") == .webkit, engine("tv.apple.com") == .chromium, engine("mobile.x.com") == .chromium else {
            throw CEFError.script("The most specific rule didn't win.")
        }
        guard SiteEngines.normalizedSite(" https://WWW.Example.com/path ") == "example.com", SiteEngines.normalizedSite("not a site") == nil,
              SiteEngines.normalizedSite("localhost") == nil else { throw CEFError.script("Site names aren't normalised.") }
        guard SiteEngines.engines(for: preferences) == [.chromium, .webkit] else { throw CEFError.script("Needed engines are wrong.") }
        var changed = preferences
        changed.siteEngineLists = ["shopping": "webkit"]
        let moves = SiteEngines.changedSites(from: preferences, to: changed)
        guard moves.contains(where: { $0.site == "instagram.com" && $0.to == .chromium }), moves.contains(where: { $0.site == "x.com" && $0.to == .chromium }),
              !moves.contains(where: { $0.site == "mobile.x.com" }), !moves.contains(where: { $0.site == "apple.com" }) else {
            throw CEFError.script("Rule changes don't move exactly the affected sites.")
        }
        guard EngineCookieSync.cookie(domain: ".apple.com", appliesTo: "music.apple.com"),
              EngineCookieSync.cookie(domain: "id.x.com", appliesTo: "x.com"),
              !EngineCookieSync.cookie(domain: ".notx.com", appliesTo: "x.com"), !EngineCookieSync.cookie(domain: "", appliesTo: "x.com") else {
            throw CEFError.script("A site's login move would copy the wrong cookies.")
        }
        guard SiteEngines.engine(for: "https://x.com/", preferences: preferences, isPrivate: true) == BrowserRuntime.engine else {
            throw CEFError.script("Private windows must use the default engine.")
        }
    }

    private static func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<300 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw CEFError.script("Timed out waiting for a per-site engine switch.")
    }
}
