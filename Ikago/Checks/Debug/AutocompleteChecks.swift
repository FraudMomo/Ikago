#if DEBUG
import Foundation

@MainActor
enum AutocompleteChecks {
    static func run() async {
        var failures = 0
        func check(_ value: Bool, _ title: String) {
            print("IKTEST autocomplete \(value ? "PASS" : "FAIL") \(title)")
            if !value { failures += 1 }
        }
        let root = FileManager.default.temporaryDirectory.appending(path: "IkagoAutocomplete-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let state = BrowserState(store: SessionStore(directory: root))
        let model = CommandPaletteModel(state: state)
        _ = state.newTab(url: "https://example.com")
        _ = state.newTab(url: "https://other.example")
        model.prepare(mode: .newTab)
        var requests: [String] = []
        model.completionProvider = { text, engine in
            requests.append(engine.rawValue + ":" + text)
            try? await Task.sleep(for: .milliseconds(text == "older" ? 500 : 10))
            return [text + " suggestion"]
        }
        model.query = "example"
        check(model.suggestions.contains { $0.tabID != nil }, "switch-tab enabled by default")
        state.browserPreferences.showSwitchToTabSuggestions = false
        check(!model.suggestions.contains { $0.tabID != nil }, "switch-tab disabled independently")
        state.browserPreferences.showSwitchToTabSuggestions = true
        try? await Task.sleep(for: .milliseconds(350))
        check(requests.isEmpty, "autocomplete defaults off without requests")
        state.browserPreferences.searchEngineAutocomplete = true
        model.query = "old"; model.query = "swift"
        try? await Task.sleep(for: .milliseconds(400))
        check(requests == ["duckduckgo:swift"] && model.completions == ["swift suggestion"], "debounce and selected engine suggestions")
        check(model.suggestions.first?.source == .whatYouTyped && model.suggestions.dropFirst().first?.title == "swift suggestion",
              "search-what-you-typed stays the default above remote suggestions")
        model.query = "https://example.com/private"
        try? await Task.sleep(for: .milliseconds(350))
        check(requests.count == 1 && model.completions.isEmpty, "addresses never requested and clear stale results")
        model.query = "older"
        try? await Task.sleep(for: .milliseconds(300))
        model.query = "newer"
        try? await Task.sleep(for: .milliseconds(800))
        check(model.completions == ["newer suggestion"], "late replies cannot replace newer results")
        state.searchEngine = .bing
        try? await Task.sleep(for: .milliseconds(400))
        check(requests.last == "bing:newer", "engine changes refresh suggestions")
        model.query = "q"
        try? await Task.sleep(for: .milliseconds(300))
        check(requests.last == "bing:q" && model.suggestions.contains { $0.source == .suggestion },
              "search predictions start from the first letter, as in Chrome")
        state.browserPreferences.searchEngineAutocomplete = false
        try? await Task.sleep(for: .milliseconds(50))
        check(model.completions.isEmpty, "disabling clears suggestions")
        model.cancelCompletions()
        let count = requests.count
        state.browserPreferences.searchEngineAutocomplete = true
        try? await Task.sleep(for: .milliseconds(350))
        check(requests.count == count, "dismissed address bar sends no requests")
        let data = Data(#"["swift",["swift"," swift tutorial ","SWIFT TUTORIAL","", "swift mac"]]"#.utf8)
        check(SearchSuggestions.parse(data, query: "swift") == ["swift tutorial", "swift mac"], "bounded parser removes blank and duplicate suggestions")
        check(SearchSuggestions.parse(Data("{}".utf8), query: "swift").isEmpty, "malformed responses ignored")
        model.completionProvider = { _, _ in throw URLError(.notConnectedToInternet) }
        model.prepare(mode: .newTab); model.query = "offline"
        try? await Task.sleep(for: .milliseconds(350))
        check(model.completions.isEmpty && !model.suggestions.isEmpty, "offline keeps direct search available")
        state.browserPreferences.searchEngineAutocomplete = false
        await omnibox(state, model, check)
        model.cancelCompletions()
        state.saveNow()
        let restored = BrowserState(store: SessionStore(directory: root))
        check(restored.browserPreferences.showSwitchToTabSuggestions == true && restored.browserPreferences.searchEngineAutocomplete == false, "toggles survive session restore")
        check(restored.history.first { $0.url == "https://github.com/" }?.typed == 4, "typed counts survive session restore")
        let legacy = try? JSONDecoder().decode(BrowserPreferences.self, from: Data(#"{"hibernationEnabled":false,"hibernationMinutes":30,"protectPinnedTabs":true,"hibernationExceptions":""}"#.utf8))
        check(legacy != nil && legacy?.searchEngineAutocomplete == nil && legacy?.showSwitchToTabSuggestions == nil, "older profiles retain safe defaults")
        let oldVisit = try? JSONDecoder().decode(Visit.self, from: Data(#"{"url":"https://a.example/","title":"A","time":1}"#.utf8))
        check(oldVisit != nil && oldVisit?.visits == nil && oldVisit?.typed == nil, "history without omnibox counts still restores")
        print("IKTEST autocompletechecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }

    /// Chrome omnibox behaviour: inline autocompletion, ranking, arrow previews and removal.
    private static func omnibox(_ state: BrowserState, _ model: CommandPaletteModel, _ check: (Bool, String) -> Void) async {
        let now = UInt64(Date().timeIntervalSince1970 * 1000), old = now - 200 * 86_400_000
        state.history = [
            Visit(url: "https://github.com/", title: "GitHub", time: now, visits: 9, typed: 3),
            Visit(url: "https://github.com/apple/swift", title: "apple/swift", time: now, visits: 2, typed: 0),
            Visit(url: "https://gitlab.com/", title: "GitLab", time: old, visits: 1, typed: 0),
            Visit(url: state.searchEngine.searchURL("swift tutorial"), title: "swift tutorial", time: now, visits: 2, typed: 1),
        ]
        var opened: [String] = [], switched: [String] = [], dismissed = 0
        model.onOpen = { url, _ in opened.append(url) }
        model.onSwitch = { switched.append($0) }
        model.onDismiss = { dismissed += 1 }
        model.prepare(mode: .newTab)
        check(model.suggestions.first?.title == "swift tutorial" && model.suggestions.first?.source == .searchHistory
              && model.suggestions.contains { $0.url == "https://github.com/" } && model.selection == -1,
              "focusing an empty field lists recent searches, then most visited pages, with nothing highlighted")
        for text in ["g", "gi", "git"] { model.userEdited(text) }
        check(model.suggestions.first?.url == "https://github.com/" && model.inlineCompletion == "hub.com",
              "typing a typed host inline-autocompletes it as the default match")
        model.userEdited("git")
        check(model.inlineCompletion.isEmpty && model.suggestions.first?.source == .whatYouTyped,
              "deleting the completion keeps what was typed and makes search the default")
        model.userEdited("gi"); model.userEdited("git"); model.userEdited("gith")
        check(model.inlineCompletion == "ub.com", "typing through the completion keeps it")
        model.commit()
        check(opened.last == "https://github.com/", "Return opens the inline-autocompleted page")
        model.prepare(mode: .newTab)
        for text in ["git", "gitl"] { model.userEdited(text) }
        check(model.inlineCompletion.isEmpty && model.suggestions.contains { $0.url == "https://gitlab.com/" },
              "pages visited once are suggested but never inline-autocompleted")
        model.prepare(mode: .newTab)
        model.userEdited("github.com/a")
        check(model.inlineCompletion.isEmpty && model.suggestions.first?.url == "https://github.com/a",
              "untyped deep pages do not complete; the typed address stays the default")
        model.prepare(mode: .newTab)
        model.userEdited("s"); model.userEdited("sw")
        check(model.suggestions.contains { $0.source == .searchHistory && $0.title == "swift tutorial" },
              "earlier searches reappear as search rows")
        let ordered = model.suggestions
        check(ordered.lastIndex(where: \.isSearch).map { last in !ordered[..<last].contains { !$0.isSearch } } == true,
              "search rows come before page rows when nothing is inline-autocompleted")
        check(!model.suggestions.contains { !$0.isSearch && OmniboxURL.searchTerms($0.url) != nil },
              "search result pages are not offered as navigation rows")
        model.prepare(mode: .newTab)
        model.userEdited("git")
        let rows = model.suggestions
        check(rows.count <= OmniboxEngine.maxResults && Set(rows.map(\.id)).count == rows.count, "results are unique and bounded")
        check(rows.map(\.id) == model.suggestions.map(\.id), "suggestion identities stay stable across renders")
        model.moveSelection(1)
        check(model.selection == 1 && model.temporaryText == rows[1].fill && model.inlineCompletion.isEmpty && model.query == "git",
              "arrowing previews a row in the field without replacing the typed text")
        model.moveSelection(100)
        check(model.selection == rows.count - 1, "the selection stops at the last row instead of wrapping")
        model.cancel()
        check(model.selection == 0 && model.temporaryText == nil && dismissed == 0, "Esc first restores the typed text")
        model.cancel()
        check(dismissed == 1, "a second Esc closes the field")
        if let index = rows.firstIndex(where: { $0.url == "https://gitlab.com/" }) {
            model.moveSelection(index)
            check(model.removeSelected() && !state.history.contains { $0.url == "https://gitlab.com/" }
                  && !model.suggestions.contains { $0.url == "https://gitlab.com/" }, "Shift+Delete forgets a history suggestion")
        } else { check(false, "history row available for removal") }
        if let tab = state.tabs.first(where: { $0.url == "https://example.com" }) {
            model.prepare(mode: .newTab); model.userEdited("example.com")
            if let index = model.suggestions.firstIndex(where: { $0.tabID == tab.id }) {
                model.moveSelection(index); model.focusNext(forward: true)
                check(model.switchFocused, "Tab moves onto the Switch to this tab button")
                model.commit()
                check(switched.last == tab.id, "Return on the focused button switches tabs instead of navigating")
            } else { check(false, "open tab offers Switch to this tab") }
            state.typedNavigations.insert(tab.id)
            tab.url = "https://github.com/"
            state.recordVisit(tabID: tab.id, url: "https://github.com/")
            check(state.history.first?.typed == 4 && state.history.first?.visits == 10 && state.typedNavigations.isEmpty,
                  "visits opened from the address field increase typed and visit counts")
        }
        if let page = state.tabs.first(where: { $0.url == "https://other.example" }) {
            state.select(page.id)
            model.prepare(mode: .currentTab)
            check(model.suggestions.first?.source == .searchHistory && model.query == "https://other.example"
                  && !model.suggestions.contains { $0.url == "https://other.example" }, "⌘L on a page lists recent searches, not the page itself")
            let before = opened.count; model.commit()
            check(opened.count == before && dismissed == 2, "Return on the untouched address keeps the page")
            model.prepare(mode: .currentTab); model.moveSelection(1)
            check(model.selection == 0 && model.temporaryText == "swift tutorial", "↓ previews the first recent search")
            model.commit()
            check(opened.last == state.searchEngine.searchURL("swift tutorial"), "Return opens the highlighted recent search")
        }
    }
}
#endif
