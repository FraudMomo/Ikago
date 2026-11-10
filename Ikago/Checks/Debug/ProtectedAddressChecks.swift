#if DEBUG
import Foundation

@MainActor
enum ProtectedAddressChecks {
    static func run(_ browser: BrowserWindowController) async {
        let state = browser.state, original = state.snapshot()
        var failures = 0
        func check(_ value: Bool, _ title: String) {
            print("IKTEST protectedaddress \(value ? "PASS" : "FAIL") \(title)")
            if !value { failures += 1 }
        }
        defer {
            browser.dismissCommandPalette()
            state.apply(original)
        }
        state.browserPreferences.searchEngineAutocomplete = false
        state.browserPreferences.showSwitchToTabSuggestions = false
        state.sidebarVisible = true
        for layout in TabLayout.allCases {
            for style in AddressStyle.allCases {
                state.tabLayout = layout
                state.addressStyle = style
                let initialIDs = Set(state.tabs.map(\.id))
                for pinned in [true, false] {
                    let savedURL = "https://saved-address.invalid/\(pinned ? "pin" : "bookmark")"
                    let tab = state.newTab(url: savedURL)!
                    if pinned { state.togglePin(tab.id) }
                    else { state.addBookmark(tab) }
                    for query in ["https://new-address.invalid/path?q=one", "protected address search"] {
                        browser.dismissCommandPalette()
                        state.select(tab.id)
                        try? await Task.sleep(for: .milliseconds(250))
                        let count = state.tabs.count
                        browser.showCommandPalette(newTab: false)
                        browser.palette.query = query
                        browser.palette.commit()
                        let expected = try? AddressResolver.resolve(query, engine: state.searchEngine)
                        check(state.tabs.count == count + (pinned ? 1 : 0)
                              && (pinned ? state.activeTabID != tab.id : state.activeTabID == tab.id)
                              && state.activeTab?.url == expected && state.activeTab?.pinned == false && state.activeTab?.folderID == nil,
                              "\(layout.rawValue)/\(style.rawValue)/\(pinned ? "pin opens separately" : "bookmarked tab navigates in place")")
                        check((!pinned || tab.url == savedURL) && tab.pinned == pinned && !browser.isEditingAddress,
                              "pin stays unchanged; address editing ends")
                        if !pinned { check(state.bookmarks.contains { $0.url == savedURL }, "bookmark retains its saved address") }
                    }
                    if !pinned, let bookmark = state.bookmarks.first(where: { $0.url == savedURL }) { state.removeBookmark(bookmark.id) }
                }
                for tab in state.tabs where !initialIDs.contains(tab.id) { state.closeTab(tab.id, removingPin: true) }
            }
        }
        let regular = state.newTab(url: "https://regular.invalid/original")!
        _ = browser.content.ensureController(for: regular)
        let count = state.tabs.count
        browser.open("https://regular.invalid/changed", inNewTab: false)
        check(state.tabs.count == count && state.activeTabID == regular.id && regular.url == "https://regular.invalid/changed",
              "ordinary tabs still navigate in place")
        state.togglePin(regular.id)
        check(!state.addressNeedsNewTab(for: regular.url + "#anchor"), "same-page fragment does not create a duplicate tab")
        let partner = state.newTab(url: "https://partner.invalid", select: false)!
        state.splitActive(with: partner.id)
        state.select(regular.id)
        let group = state.splitGroup(of: regular.id)
        browser.open("https://separate.invalid", inNewTab: false)
        check(state.splitGroup(of: regular.id) == group && state.splitGroup(of: state.activeTabID ?? "") == nil,
              "protected address navigation leaves the original split intact")
        state.select(regular.id)
        while state.tabs.count < Session.maxTabs { _ = state.newTab(url: "about:blank", select: false) }
        browser.open("https://at-capacity.invalid", inNewTab: false)
        check(state.activeTabID == regular.id && regular.url == "https://regular.invalid/changed" && regular.pinned,
              "tab capacity never falls back to overwriting the pin")
        print("IKTEST protectedaddresschecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }
}
#endif
