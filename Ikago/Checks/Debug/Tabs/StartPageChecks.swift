#if DEBUG
import AppKit
import Foundation

/// Pages Ikago opens on its own follow the person's choices, never a fixed site: the first tab, Split View's new pane
/// and a new private window. ⌘⇧T skips new tabs closed untouched.
@MainActor
enum StartPageChecks {
    static func run(_ browser: BrowserWindowController) async {
        var failures = 0
        func check(_ value: Bool, _ title: String) {
            print("IKTEST startpage \(value ? "PASS" : "FAIL") \(title)")
            if !value { failures += 1 }
        }
        let root = FileManager.default.temporaryDirectory.appending(path: "IkagoStartPage-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let state = BrowserState(store: SessionStore(directory: root))
        state.searchEngine = .google
        state.newTabMode = .commandBar
        check(state.startPageURL == "https://www.google.com", "the start page is the chosen engine's")
        state.newTabMode = .homepage
        state.homepage = "example.org"
        check(state.startPageURL.hasPrefix("https://example.org"), "with Homepage chosen it is the homepage")
        state.newTabMode = .commandBar
        let first = state.newTab(url: "https://example.com")!
        state.splitActive()
        let pane = state.splitGroup(of: first.id)?.first { $0 != first.id }.flatMap(state.tab)
        check(pane?.url == "https://www.google.com", "Split View's new pane opens the start page, not a fixed site")

        // ⌘⇧T skips new tabs that were closed untouched, like Chrome's New Tab page.
        state.newTabMode = .homepage
        let untouched = state.newTab(url: state.startPageURL)!
        state.closeTab(untouched.id)
        check(state.closed.first?.url != untouched.url, "an untouched homepage tab leaves nothing to reopen")
        let used = state.newTab(url: state.startPageURL)!
        used.canGoBack = true
        state.closeTab(used.id)
        check(state.closed.first?.url == used.url, "a homepage tab that was used is reopened")
        let page = state.newTab(url: "https://example.net/page")!
        state.closeTab(page.id)
        check(state.closed.first?.url == page.url, "ordinary pages are still reopened")
        state.newTabMode = .commandBar

        // Ikago Home: the start page and every new tab, each a tab of its own; closed untouched it leaves nothing.
        state.newTabMode = .home
        check(state.startPageURL == "ikago://home", "with Ikago Home chosen the start page is Ikago Home")
        let home = state.newTab(url: state.startPageURL)!
        state.closeTab(home.id)
        check(state.closed.first?.url != home.url, "an untouched Ikago Home tab leaves nothing to reopen")
        state.newTabMode = .commandBar
        let mainState = browser.state, savedMode = mainState.newTabMode
        mainState.newTabMode = .home
        let before = mainState.tabs.filter { $0.url == "ikago://home" }.count
        browser.newTab(); browser.newTab()
        check(mainState.tabs.filter { $0.url == "ikago://home" }.count == before + 2, "each new tab opens its own Ikago Home")
        for tab in mainState.tabs where tab.url == "ikago://home" { mainState.closeTab(tab.id) }
        mainState.newTabMode = savedMode

        // A private window opens like ⌘N: with the command bar, no page loads by itself.
        let main = browser.state
        let saved = (main.newTabMode, main.searchEngine)
        main.newTabMode = .commandBar; main.searchEngine = .bing
        (NSApp.delegate as? AppDelegate)?.openPrivateWindow()
        try? await Task.sleep(for: .milliseconds(600))
        let window = NSApp.windows.compactMap { $0.windowController as? BrowserWindowController }.last { $0.state.isPrivate }
        check(window != nil && window?.state.tabs.allSatisfy { !$0.url.contains("duckduckgo") } == true,
              "a private window opens no fixed site")
        check(window?.isEditingAddress == true, "a private window offers the command bar like ⌘N")
        window?.window?.close()
        (main.newTabMode, main.searchEngine) = saved
        print("IKTEST startpagechecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }
}
#endif
