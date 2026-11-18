#if DEBUG
import AppKit
import Foundation

/// Pages Ikago opens on its own follow the person's choices, never a fixed site: the first tab, Split View's new pane
/// and a new private window.
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
