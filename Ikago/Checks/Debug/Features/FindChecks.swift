#if DEBUG
import AppKit
import Foundation

/// Find in page on whichever engine runs: "N of M", next and previous (wrapping), Match Case, WebKit's tick marks, each
/// tab's own remembered search, and the search following a tab switch. The fixture page has "apple" four times when case
/// is ignored and three times when it isn't.
@MainActor
enum FindChecks {
    static func run(_ browser: BrowserWindowController, base: String) async {
        var failures = 0
        func check(_ value: Bool, _ title: String) {
            print("IKTEST find \(value ? "PASS" : "FAIL") \(title)")
            if !value { failures += 1 }
        }
        func settle(_ ms: Int = 900) async { try? await Task.sleep(for: .milliseconds(ms)) }
        let find = browser.find
        let savedCase = find.matchCase
        find.matchCase = false
        let state = browser.state
        guard let first = state.newTab(url: base + "/find.html?a") else { return finish(failures) }
        await settle(2500)
        let engine = browser.activeController?.page is CEFWebTab ? "chromium" : "webkit"
        print("IKTEST find engine=\(engine)")

        browser.showFindBar()
        await settle(400)  // the field takes the keyboard, as it does before anyone types
        // Typed letter by letter, like a person: each letter searches again from where the last one was.
        // The field searches as its text changes, as when typing (a second search would count as Find Next).
        for prefix in ["a", "ap", "app", "appl", "apple"] {
            find.text = prefix
            await settle(250)
        }
        await settle()
        check(find.totalMatches == 4 && find.activeMatch == 1, "typing a search shows 1 of 4 (got \(find.activeMatch) of \(find.totalMatches ?? -1))")
        browser.findNextMatch(nil); await settle()
        check(find.activeMatch == 2, "Find Next moves to 2 of 4 (got \(find.activeMatch))")
        browser.findPreviousMatch(nil); await settle()
        browser.findPreviousMatch(nil); await settle()
        check(find.activeMatch == 4, "Find Previous wraps from the first match to the last (got \(find.activeMatch))")
        find.matchCase = true; await settle()
        check(find.totalMatches == 3, "Match Case counts 3 (got \(find.totalMatches ?? -1))")
        find.matchCase = false; await settle()
        if engine == "webkit" {
            let ticks = browser.activeController?.findTicks
            check(ticks?.isHidden == false, "WebKit pages show where the matches are along the edge")
        }

        // Find belongs to each tab: a new tab starts empty, with its bar closed.
        guard let second = state.newTab(url: base + "/find.html?b") else { return finish(failures) }
        await settle(2000)
        check(!browser.chrome.showFind, "a newly selected tab without its own search hides the find bar")
        browser.showFindBar()
        check(find.text.isEmpty, "a tab's find starts empty, never from another tab's search (got \(find.text))")
        await settle(400)  // the field appears before anyone types in it
        find.text = "banana"; await settle()
        check(find.totalMatches == 1, "banana is found once")

        // Switching back brings the first tab's own bar and search; switching again brings the second's.
        state.select(first.id); await settle(1200)
        check(browser.chrome.showFind && find.text == "apple" && find.totalMatches == 4,
              "the first tab brings back its own open bar and search (got \(find.text), \(find.totalMatches ?? -1))")
        state.select(second.id); await settle(1200)
        check(browser.chrome.showFind && find.text == "banana" && find.totalMatches == 1, "the second tab keeps its own search")
        browser.closeFindBar()
        state.select(first.id); await settle(800)
        check(browser.chrome.showFind && find.text == "apple", "closing one tab's bar leaves the other tab's open")
        browser.closeFindBar()
        state.select(second.id); await settle(500)
        check(!browser.chrome.showFind, "a closed bar stays closed when its tab comes back")
        browser.showFindBar()
        check(find.text == "banana", "reopening a tab's find starts from its own last search")
        browser.closeFindBar()
        find.matchCase = savedCase
        finish(failures)
    }

    /// Types a search fast, then reports what the page still marks: the Highlight All ranges and the selection.
    static func trailProbe(_ browser: BrowserWindowController, base: String) async {
        let find = browser.find
        find.highlightAll = ProcessInfo.processInfo.environment["IKAGO_FIND_HIGHLIGHT_ALL"] != "0"
        guard browser.state.newTab(url: base + "/find.html?trail") != nil else { return }
        try? await Task.sleep(for: .milliseconds(2500))
        browser.showFindBar()
        try? await Task.sleep(for: .milliseconds(400))
        let words = ["p", "pi", "pin", "pine", "pinea", "pineap", "pineapp", "pineappl", "pineapple"]
        let sequence = ProcessInfo.processInfo.environment["IKAGO_FIND_BACK"] == "1" ? words + words.reversed().dropFirst().prefix(6) : words
        for prefix in sequence {
            find.text = prefix
            try? await Task.sleep(for: .milliseconds(40))
        }
        try? await Task.sleep(for: .milliseconds(1500))
        let script = "const h = window.CSS && CSS.highlights ? CSS.highlights.get('ikago-find-all') : null; JSON.stringify({marks: h ? [...h].map(r => r.toString()) : null, selection: String(window.getSelection())})"
        let result = try? await browser.activeController?.page?.evaluate(script)
        print("IKTEST findtrail text=\(find.text) \(find.activeMatch) of \(find.totalMatches ?? -1) page=\(result.map { "\($0)" } ?? "nil")")
    }

    private static func finish(_ failures: Int) {
        print("IKTEST findchecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }
}
#endif
