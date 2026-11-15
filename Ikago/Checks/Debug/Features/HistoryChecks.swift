#if DEBUG
import AppKit

/// History grouping (`HistoryGroup`) and Clear Browsing Data (`BrowserState.clearData`): each period removes only its
/// visits, search pages follow their own checkbox, and the other kinds clear only when asked.
@MainActor
enum HistoryChecks {
    static func run(_ browser: BrowserWindowController) async {
        let state = browser.state, original = state.snapshot()
        var failures = 0
        func check(_ value: Bool, _ title: String) {
            print("IKTEST history \(value ? "PASS" : "FAIL") \(title)")
            if !value { failures += 1 }
        }
        defer {
            state.apply(original)
            print("IKTEST historychecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
        }
        let now = Date(), calendar = Calendar.current
        func visit(_ url: String, _ date: Date) -> Visit { Visit(url: url, title: url, time: UInt64(date.timeIntervalSince1970 * 1000)) }
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .hour, value: -12, to: today)!
        let older = calendar.date(byAdding: .day, value: -5, to: today)!.addingTimeInterval(3600)
        func seed() {
            state.history = [
                visit("https://www.recent.example/a", now.addingTimeInterval(-600)),
                visit("https://www.google.com/search?q=recent", now.addingTimeInterval(-300)),
                visit("https://today.example/", max(today.addingTimeInterval(60), now.addingTimeInterval(-7200))),
                visit("https://yesterday.example/", yesterday),
                visit("https://older.example/", older),
                visit("https://www.recent.example/b", older.addingTimeInterval(60)),
            ]
            state.closed = [SavedTab(id: "closed-probe", url: "https://closed.example/", title: "Closed", pinned: false)]
        }

        seed()
        let byDate = HistoryGroup.build(state.history, query: "", by: .date)
        check(byDate.first?.title == "Today" && byDate.dropFirst().first?.title == "Yesterday" && byDate.count == 3,
              "visits group by day, newest day first")
        check(byDate.allSatisfy { group in zip(group.visits, group.visits.dropFirst()).allSatisfy { $0.time >= $1.time } },
              "each day lists its newest visit first")
        let bySite = HistoryGroup.build(state.history, query: "", by: .site)
        check(bySite.first(where: { $0.title == "recent.example" })?.visits.count == 2, "by site, www. pages join their site")
        check(HistoryGroup.build(state.history, query: "older", by: .date).flatMap(\.visits).map(\.url) == ["https://older.example/"],
              "search keeps only matching pages")

        var request = ClearDataRequest()
        request.period = .lastHour; request.searches = false
        _ = await state.clearData(request)
        check(!state.history.contains { $0.url.hasSuffix("/a") } && state.history.contains { $0.url.contains("search?q=recent") },
              "Last Hour removes the hour's pages but keeps searches when unticked")
        check(state.history.contains { $0.url == "https://yesterday.example/" } && state.closed.count == 1,
              "Last Hour keeps older visits and recently closed tabs")

        seed()
        request = ClearDataRequest(); request.period = .allTime; request.history = false
        _ = await state.clearData(request)
        check(!state.history.contains(where: \.isSearch) && state.history.count == 5, "Search history alone removes only searches")

        seed()
        request = ClearDataRequest(); request.period = .sinceYesterday; request.closedTabs = true
        _ = await state.clearData(request)
        check(state.history.map(\.url).sorted() == ["https://older.example/", "https://www.recent.example/b"],
              "Since Yesterday removes today and yesterday only")
        check(state.closed.isEmpty, "recently closed tabs clear when ticked")

        seed()
        request = ClearDataRequest(); request.period = .custom; request.from = older; request.to = older
        _ = await state.clearData(request)
        check(!state.history.contains { calendar.isDate($0.date, inSameDayAs: older) } && state.history.count == 4,
              "a custom range removes the days it covers")

        // The modal, the History page and Settings ▸ History.
        browser.showClearData()
        try? await Task.sleep(for: .milliseconds(300))
        check(browser.chrome.showClearData, "Clear… opens the Clear Browsing Data modal")
        browser.chrome.showClearData = false
        check(SettingsCategory.navigationGroups.joined().contains(.history), "Settings lists History")
        check(PaletteAction.matching("clear browsing data").first?.selector == NSSelectorFromString("clearBrowsingHistory:"),
              "the address bar finds Clear Browsing Data")
    }
}
#endif
