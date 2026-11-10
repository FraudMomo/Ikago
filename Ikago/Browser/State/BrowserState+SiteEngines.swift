import Foundation

/// Changing which engine opens which site (Settings ▸ Engine, the site popover). Sites that now use another engine
/// take their logins along (`EngineCookieSync.rulesChanged`).
extension BrowserState {
    /// Posted after site rules change, so open tabs can follow.
    static let siteEnginesChanged = Notification.Name("IkagoSiteEnginesChanged")

    /// nil: the site follows its list or the default engine again.
    func setSiteEngine(_ engine: BrowserEngine?, for site: String) {
        updateSiteEngines { preferences in
            var rules = preferences.siteEngines ?? [:]
            rules[site] = engine?.rawValue
            preferences.siteEngines = rules.isEmpty ? nil : rules
        }
    }

    /// nil: the list's sites follow the default engine.
    func setListEngine(_ engine: BrowserEngine?, for list: String) {
        updateSiteEngines { preferences in
            var lists = preferences.siteEngineLists ?? [:]
            lists[list] = engine?.rawValue
            preferences.siteEngineLists = lists.isEmpty ? nil : lists
        }
    }

    /// A rule asks for Chromium, which this launch doesn't run (it starts only at launch).
    var siteEnginesNeedRelaunch: Bool {
        SiteEngines.engines(for: browserPreferences).contains(.chromium) && !BrowserRuntime.runs(.chromium)
    }

    /// The site a rule for this page's address should name: its registrable domain (mobile.x.com → x.com).
    static func siteForRule(_ url: String) -> String? {
        guard let host = URL(string: url)?.host?.lowercased(), ["http", "https"].contains(URL(string: url)?.scheme?.lowercased() ?? "") else { return nil }
        return SiteEngines.normalizedSite(PublicSuffix.registrableDomain(host))
    }

    private func updateSiteEngines(_ change: (inout BrowserPreferences) -> Void) {
        guard !isPrivate else { return }
        let old = browserPreferences
        change(&browserPreferences)
        guard old != browserPreferences else { return }
        saveNow()
        let new = browserPreferences, profiles = Set(spaces.map(\.profileID))
        // Tabs follow once the sites' sign-ins are in their new engine, so they don't open signed out.
        Task { @MainActor in
            await EngineCookieSync.rulesChanged(from: old, to: new, profiles: profiles)
            NotificationCenter.default.post(name: Self.siteEnginesChanged, object: self)
        }
    }
}
