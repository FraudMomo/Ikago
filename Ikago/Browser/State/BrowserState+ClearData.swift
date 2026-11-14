import Foundation

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
