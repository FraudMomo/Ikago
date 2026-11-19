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
/// A site's saved choice for one kind of permission (camera, microphone, notifications): ask each time, allow (for good,
/// or until `SitePermissions.expires`), or block.
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

/// How long an allow from the permission prompt lasts.
enum PermissionGrant: String, CaseIterable, Identifiable {
    /// While the tab stays on the site (not saved).
    case visit
    /// For 24 hours.
    case day
    /// Until changed.
    case always
    var id: String { rawValue }
    var title: String {
        switch self {
        case .visit: "Allow Once"
        case .day: "Allow for a Day"
        case .always: "Always Allow"
        }
    }
    static let dayLength: TimeInterval = 24 * 60 * 60
}

/// The answer to a permission prompt. Dismissing it (Esc, closing) denies only this request and saves nothing.
enum PermissionChoice: Equatable {
    case allow(PermissionGrant)
    case block
    case dismiss
}

/// Per site (host): unset kinds ask. Camera, microphone and notifications keep their own fields (saved before the
/// rest); every other kind lives in `others`, by its catalog key (`PermissionRequest.Kinds.catalog`).
struct SitePermissions: Codable, Equatable {
    var camera: SitePermission? = nil
    var microphone: SitePermission? = nil
    var notifications: SitePermission? = nil
    var others: [String: SitePermission]? = nil
    /// When a time-limited allow ends, by kind key; past it, the kind asks again.
    var expires: [String: Date]? = nil
    /// The kinds the site has asked for, by key: the site card lists these (and any changed), not the whole catalog.
    var requested: [String]? = nil

    subscript(key: String) -> SitePermission? {
        get {
            switch key {
            case "camera": camera
            case "microphone": microphone
            case "notifications": notifications
            default: others?[key]
            }
        }
        set {
            switch key {
            case "camera": camera = newValue
            case "microphone": microphone = newValue
            case "notifications": notifications = newValue
            default:
                var all = others ?? [:]
                all[key] = newValue
                others = all.isEmpty ? nil : all
            }
        }
    }
}

/// "Allow Once": the kinds a tab may use while it stays on `host`. Kept in memory only.
struct VisitGrant: Equatable {
    let host: String
    var kinds: PermissionRequest.Kinds
}

extension BrowserState {
    /// The site's saved choice for one kind: an allow past its expiry asks again.
    func sitePermission(_ kind: PermissionRequest.Kinds, host: String) -> SitePermission {
        let saved = browserPreferences.sitePermissions?[host.lowercased()]
        let value = saved?[kind.key] ?? .ask
        if value == .allow, let until = saved?.expires?[kind.key], until <= Date() { return .ask }
        return value
    }

    /// When the site's allow for `kind` ends, if it is time-limited and still running.
    func sitePermissionExpiry(_ kind: PermissionRequest.Kinds, host: String) -> Date? {
        guard sitePermission(kind, host: host) == .allow else { return nil }
        return browserPreferences.sitePermissions?[host.lowercased()]?.expires?[kind.key]
    }

    func setSitePermission(_ value: SitePermission, _ kind: PermissionRequest.Kinds, host: String, until: Date? = nil) {
        let host = host.lowercased()
        var all = browserPreferences.sitePermissions ?? [:]
        var entry = all[host] ?? SitePermissions()
        let stored: SitePermission? = value == .ask ? nil : value
        entry[kind.key] = stored
        var expires = entry.expires ?? [:]
        expires[kind.key] = value == .allow ? until : nil
        entry.expires = expires.isEmpty ? nil : expires
        all[host] = entry == SitePermissions() ? nil : entry
        browserPreferences.sitePermissions = all.isEmpty ? nil : all
    }

    /// Notes that a site asked for these kinds, so its card lists them. Private windows note nothing.
    func noteRequested(_ kinds: PermissionRequest.Kinds, origin: String) {
        guard !isPrivate, let host = URL(string: origin)?.host?.lowercased() else { return }
        var all = browserPreferences.sitePermissions ?? [:]
        var entry = all[host] ?? SitePermissions()
        let keys = kinds.parts.map(\.key).filter { !(entry.requested ?? []).contains($0) }
        guard !keys.isEmpty else { return }
        entry.requested = (entry.requested ?? []) + keys
        all[host] = entry
        browserPreferences.sitePermissions = all
    }

    /// The kinds a site's card lists: those it asked for, those set to anything but Ask, and this visit's grants.
    func listedPermissions(host: String, tabID: String?) -> [PermissionRequest.Kinds] {
        let entry = browserPreferences.sitePermissions?[host.lowercased()]
        let visit = tabID.flatMap { visitGrants[$0] }.flatMap { $0.host == host.lowercased() ? $0.kinds : nil } ?? []
        return PermissionRequest.Kinds.each.filter { kind in
            entry?.requested?.contains(kind.key) == true || entry?[kind.key] != nil || visit.contains(kind)
        }
    }

    /// Forgets everything saved for a site's permissions, what it asked for included.
    func resetSitePermissions(host: String) {
        var all = browserPreferences.sitePermissions ?? [:]
        all[host.lowercased()] = nil
        browserPreferences.sitePermissions = all.isEmpty ? nil : all
    }

    /// A kind's standing for a tab: its Allow Once while it is still on that site, else the site's saved choice.
    func permission(_ kind: PermissionRequest.Kinds, host: String, tabID: String?) -> SitePermission {
        if let tabID, let grant = visitGrants[tabID], grant.host == host.lowercased(), grant.kinds.contains(kind) { return .allow }
        return sitePermission(kind, host: host)
    }

    /// What the site's choices decide for a request: blocked if any asked-for kind is blocked, allowed if every one is
    /// allowed (for good, for now, or for this visit of `tabID`), otherwise nil (ask). Private windows keep nothing but
    /// their visits' grants.
    func rememberedDecision(origin: String, kinds: PermissionRequest.Kinds, tabID: String? = nil) -> PermissionRequest.Decision? {
        guard let host = URL(string: origin)?.host?.lowercased() else { return nil }
        let asked = PermissionRequest.Kinds.each.filter { kinds.contains($0) }
        let choices = asked.map { isPrivate ? permissionForVisit($0, host: host, tabID: tabID) : permission($0, host: host, tabID: tabID) }
        if choices.contains(.block) { return .deny }
        if !choices.isEmpty, choices.allSatisfy({ $0 == .allow }) { return .allow }
        return nil
    }

    private func permissionForVisit(_ kind: PermissionRequest.Kinds, host: String, tabID: String?) -> SitePermission {
        guard let tabID, let grant = visitGrants[tabID], grant.host == host, grant.kinds.contains(kind) else { return .ask }
        return .allow
    }

    /// Records the prompt's answer for every kind it asked about. A private window remembers nothing past the visit.
    func applyPermission(_ choice: PermissionChoice, kinds: PermissionRequest.Kinds, origin: String, tabID: String) {
        guard let host = URL(string: origin)?.host?.lowercased() else { return }
        let asked = PermissionRequest.Kinds.each.filter { kinds.contains($0) }
        switch choice {
        case .dismiss: return
        case .allow(.visit):
            var grant = visitGrants[tabID].flatMap { $0.host == host ? $0 : nil } ?? VisitGrant(host: host, kinds: [])
            grant.kinds.formUnion(kinds)
            visitGrants[tabID] = grant
        case .allow(let grant):
            guard !isPrivate else { return applyPermission(.allow(.visit), kinds: kinds, origin: origin, tabID: tabID) }
            let until = grant == .day ? Date().addingTimeInterval(PermissionGrant.dayLength) : nil
            asked.forEach { setSitePermission(.allow, $0, host: host, until: until) }
        case .block:
            guard !isPrivate else { return }
            asked.forEach { setSitePermission(.block, $0, host: host) }
        }
    }

    /// Allow Once lasts while the tab stays on its site: leaving it, or closing the tab, ends it.
    func endVisitGrant(tabID: String, unless host: String? = nil) {
        guard let grant = visitGrants[tabID], grant.host != host?.lowercased() else { return }
        visitGrants[tabID] = nil
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
