import Foundation
import WebKit

// MARK: - Privacy
/// Clearing browsing data (Settings ▸ Privacy, and "clear when quitting").
extension BrowserState {
    var clearsDataOnQuit: Bool { browserPreferences.clearDataOnQuit == true && !isPrivate }

    /// Forgets history, recently closed tabs, cached favicons and every Space's website data
    /// (cookies, logins, storage). Open tabs, bookmarks and settings stay.
    func clearBrowsingData() async {
        let knownURLs = history.map(\.url) + tabs.map(\.url)
        history.removeAll()
        closed.removeAll()
        FaviconCache.shared.clear()
        for profileID in Set(spaces.map(\.profileID)) {
            // A Chromium clear that fails finishes on the next launch, so "clear when quitting" can't leave data behind.
            do { try await EngineCookieSync.clearBothEngines(profile: profileID, knownURLs: knownURLs) }
            catch { NSLog("Ikago: Chromium data not cleared for a Space, retrying next launch: %@", error.localizedDescription) }
        }
        DownloadCenter.shared.clearFinished()  // the list and its source URLs; never the files
        saveNow()
        store.discardBackup()
    }
}

// MARK: - ClearData
/// What Clear Browsing Data removes and over which period (the History page, Settings ▸ History and ▸ Privacy, and the
/// address bar's action all open the same modal).
struct ClearDataRequest: Equatable {
    enum Period: String, CaseIterable, Identifiable {
        case lastHour, today, sinceYesterday, allTime, custom
        var id: String { rawValue }
        var title: String {
            switch self {
            case .lastHour: "Last Hour"
            case .today: "Today"
            case .sinceYesterday: "Since Yesterday"
            case .allTime: "All Time"
            case .custom: "Custom…"
            }
        }
    }

    var period = Period.lastHour
    var from = Calendar.current.date(byAdding: .day, value: -7, to: Calendar.current.startOfDay(for: Date())) ?? Date()
    var to = Date()
    var history = true
    /// Search result pages, which the address bar lists as earlier searches.
    var searches = true
    var siteData = false
    var cache = false
    var closedTabs = false
    var downloads = false
    var icons = false

    var isEmpty: Bool { !(history || searches || siteData || cache || closedTabs || downloads || icons) }

    /// The period as dates; nil for all time.
    func interval(now: Date = Date()) -> DateInterval? {
        let calendar = Calendar.current
        switch period {
        case .lastHour: return DateInterval(start: now.addingTimeInterval(-3600), end: now)
        case .today: return DateInterval(start: calendar.startOfDay(for: now), end: now)
        case .sinceYesterday:
            let start = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)) ?? now
            return DateInterval(start: start, end: now)
        case .allTime: return nil
        case .custom:
            let start = calendar.startOfDay(for: min(from, to))
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: max(from, to))) ?? now
            return DateInterval(start: start, end: min(end, now))
        }
    }
}

extension Visit {
    var date: Date { Date(timeIntervalSince1970: Double(time) / 1000) }
    var isSearch: Bool { OmniboxURL.searchTerms(url) != nil }
}

extension BrowserState {
    /// The visits in a period (all of them for nil).
    func visits(in period: DateInterval?) -> [Visit] {
        guard let period else { return history }
        return history.filter { period.contains($0.date) }
    }

    /// Clears what `request` asks for, in every Space and window. Returns a problem to show, if any part failed.
    func clearData(_ request: ClearDataRequest) async -> String? {
        let root = primary ?? self
        guard !root.isFrozen else { return nil }
        let period = request.interval()
        let visited = root.visits(in: period).map(\.url)
        if request.history || request.searches {
            // On the first window's state: it saves, and the other windows take the shared history from it.
            root.history.removeAll { visit in
                (period?.contains(visit.date) ?? true) && (visit.isSearch ? request.searches : request.history)
            }
        }
        if request.closedTabs { for state in root.windowGroup { state.closed.removeAll() } }
        if request.icons { FaviconCache.shared.clear() }
        if request.downloads { DownloadCenter.shared.clearFinished(in: period) }
        var issue: String?
        if request.siteData || request.cache {
            let known = period == nil ? visited + root.windowGroup.flatMap { $0.tabs.map(\.url) } : visited
            for profile in Set(root.spaces.map(\.profileID)) {
                do {
                    try await EngineCookieSync.clear(profile: profile, knownURLs: known, storage: request.siteData,
                                                     cache: request.cache, since: period?.start)
                } catch { issue = "Some Chromium data couldn’t be cleared: \(error.localizedDescription)" }
            }
        }
        // Nothing cleared may linger in the session's backup.
        root.saveNow()
        root.store.discardBackup()
        return issue
    }
}

// MARK: - SitePermissions
/// A site's camera, microphone and notification choice (the site popover): ask each time, always allow, or always block.
enum SitePermission: String, Codable, CaseIterable, Identifiable {
    case ask, allow, block
    var id: String { rawValue }
    var title: String {
        switch self {
        case .ask: "Ask"
        case .allow: "Allow"
        case .block: "Block"
        }
    }
}

/// Per site (host): unset kinds ask.
struct SitePermissions: Codable, Equatable {
    var camera: SitePermission? = nil
    var microphone: SitePermission? = nil
    var notifications: SitePermission? = nil
}

extension BrowserState {
    func sitePermission(_ kind: PermissionRequest.Kinds, host: String) -> SitePermission {
        let saved = browserPreferences.sitePermissions?[host.lowercased()]
        return (kind == .camera ? saved?.camera : kind == .notifications ? saved?.notifications : saved?.microphone) ?? .ask
    }

    func setSitePermission(_ value: SitePermission, _ kind: PermissionRequest.Kinds, host: String) {
        let host = host.lowercased()
        var all = browserPreferences.sitePermissions ?? [:]
        var entry = all[host] ?? SitePermissions()
        let stored: SitePermission? = value == .ask ? nil : value
        if kind == .camera { entry.camera = stored } else if kind == .notifications { entry.notifications = stored } else { entry.microphone = stored }
        all[host] = entry == SitePermissions() ? nil : entry
        browserPreferences.sitePermissions = all.isEmpty ? nil : all
    }

    /// What the site's saved choices decide for a request: blocked if any asked-for kind is blocked, allowed if every
    /// one is allowed, otherwise nil (ask). Private windows always ask.
    func rememberedDecision(origin: String, kinds: PermissionRequest.Kinds) -> PermissionRequest.Decision? {
        guard !isPrivate, let host = URL(string: origin)?.host else { return nil }
        let asked = [PermissionRequest.Kinds.camera, .microphone, .notifications].filter { kinds.contains($0) }
        let choices = asked.map { sitePermission($0, host: host) }
        if choices.contains(.block) { return .deny }
        if !choices.isEmpty, choices.allSatisfy({ $0 == .allow }) { return .allow }
        return nil
    }

    /// Settings ▸ Memory's "always keep these sites awake", for one host.
    func keepsAwake(_ host: String) -> Bool { browserPreferences.protects("https://\(host)") }

    func setKeepsAwake(_ on: Bool, host: String) {
        var entries = browserPreferences.hibernationExceptions.split(whereSeparator: { $0 == "," || $0.isWhitespace }).map(String.init)
        entries.removeAll { $0.lowercased() == host.lowercased() }
        if on { entries.append(host) }
        browserPreferences.hibernationExceptions = entries.joined(separator: ", ")
    }
}

// MARK: - SiteEngines
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
