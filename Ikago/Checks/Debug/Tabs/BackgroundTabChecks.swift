#if DEBUG
import Foundation

@MainActor
enum BackgroundTabChecks {
    static func run(_ browser: BrowserWindowController, base: String) async {
        let state = browser.state, original = state.snapshot()
        var failures = 0
        func check(_ value: Bool, _ title: String) {
            print("IKTEST backgroundtabs \(value ? "PASS" : "FAIL") \(title)")
            if !value { failures += 1 }
        }
        defer { state.apply(original) }
        guard URL(string: base)?.host == "127.0.0.1" else { check(false, "requires loopback fixture"); return }
        state.browserPreferences.loadBackgroundTabs = true
        let selected = state.newTab(url: base + "/?selected")!
        let tab = state.newTabFromLink(url: base + "/?background", opener: selected, select: false)!
        for _ in 0..<60 {
            if tab.title == "Ikago fixture", !tab.isLoading { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        check(browser.content.controller(for: tab.id)?.page != nil && tab.title == "Ikago fixture" && !tab.isLoading,
              "new background link loads and finishes before selection")
        check(state.activeTabID == selected.id, "background load leaves foreground selection unchanged")
        state.select(tab.id)
        check(browser.content.controller(for: tab.id)?.page != nil, "selecting the already loaded tab retains its page")
        state.browserPreferences.loadBackgroundTabs = false
        let deferred = state.newTab(url: base + "/?deferred", select: false)!
        try? await Task.sleep(for: .milliseconds(300))
        check(browser.content.controller(for: deferred.id)?.page == nil, "optional deferred loading does not start a background page")
        state.select(deferred.id)
        try? await Task.sleep(for: .milliseconds(500))
        check(browser.content.controller(for: deferred.id)?.page != nil, "deferred tab starts when selected")
        var restored = state.snapshot()
        let id = UUID().uuidString
        restored.tabs.append(SavedTab(id: id, url: base + "/?restored", title: "", pinned: false))
        restored.browser?.loadBackgroundTabs = true
        state.apply(restored)
        try? await Task.sleep(for: .milliseconds(300))
        check(state.activeTabID.flatMap { browser.content.controller(for: $0)?.tab } === state.activeTab, "restored controllers attach to the current tab model")
        check(browser.content.controller(for: id)?.page == nil, "session restore does not preload every dormant tab")
        state.select(id)
        try? await Task.sleep(for: .milliseconds(500))
        check(browser.content.controller(for: id)?.page != nil, "restored tab loads on selection")
        print("IKTEST backgroundtabchecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }
}
#endif
