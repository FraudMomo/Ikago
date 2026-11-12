#if DEBUG
import AppKit
import WebKit

@MainActor
enum FeatureBatchChecks {
    static func run(_ browser: BrowserWindowController) async {
        let state = browser.state, saved = state.snapshot()
        guard let window = browser.window else { return }
        let originalFrame = window.frame
        var failures = 0
        func check(_ value: Bool, _ label: String) {
            if !value { failures += 1 }
            print("IKTEST featurebatch \(value ? "PASS" : "FAIL") \(label)")
        }
        func settle() async { try? await Task.sleep(for: .milliseconds(450)) }
        defer {
            if window.isInFullScreen { window.toggleFullScreen(nil) }
            state.barCondensed = false
            state.apply(saved)
            window.setFrame(originalFrame, display: true)
        }
        state.tabs = []; state.folders = []; state.splits = []
        state.tabLayout = .vertical
        let a = state.newTab(url: InternalPage.notes.url)!
        let b = state.newTab(url: InternalPage.performance.url)!
        let child = state.newTabFromLink(url: InternalPage.history.url, opener: b, select: true)!
        state.closeTab(child.id)
        check(state.activeTabID == b.id, "closing child returns to previously selected opener")
        state.select(a.id); state.select(b.id)
        state.closeTab(b.id)
        check(state.activeTabID == a.id, "closing active tab returns to last visited tab")
        let pin = state.newTab(url: "http://127.0.0.1:1/pin")!
        state.togglePin(pin.id); pin.pinAsRow = true
        let restoredPin = try? JSONDecoder().decode(SavedTab.self, from: JSONEncoder().encode(pin.saved))
        check(restoredPin?.pinAsRow == true && !state.sidebarGridPinnedTabs.contains { $0.id == pin.id }, "row pin survives session roundtrip and leaves grid")
        state.select(a.id)
        let file = SessionStore.testDirectory.appending(path: "unload-check.html")
        try? Data("<title>Unload check</title><h1>Unload</h1>".utf8).write(to: file)
        let live = state.newTab(url: file.absoluteString)!
        await settle()
        check(browser.content.controller(for: live.id)?.page != nil, "unload fixture has a live native page")
        browser.unloadTab(live.id)
        await settle()
        check(live.isHibernating && browser.content.controller(for: live.id)?.page == nil && state.tab(live.id) != nil, "explicit unload releases native page and retains tab")
        check(state.activeTabID == a.id, "unload returns to another tab")
        let isolated = BrowserState(privateFrom: state)
        let last = isolated.newTab(url: "https://last-tab.invalid/")!
        check(isolated.unloadTab(last.id) == last.id && isolated.activeTabID == nil && last.isHibernating,
              "the final tab can unload into an empty page without deleting its identity")
        let json = try? BrowserSecurity.trackerJSON(exceptions: ["youtube.com"])
        check(json?.contains("unless-top-url") == true && json?.contains("youtube") == true, "site recovery excludes top origin from built-in tracker rules")
        check(state.browserPreferences.pageIntelligence != true, "page AI remains opt-in")
        for (label, passed) in NotesPage.storageChecksForTests(state) { check(passed, label) }

        state.tabLayout = .vertical; state.sidebarVisible = true
        state.browserPreferences.sidebarCompact = false
        state.sidebarOnRight = true
        state.select(a.id)
        await settle()
        if let frame = LayoutChecks.frames["content"], let shell = LayoutChecks.frames["shell"] {
            check(frame.maxX < shell.maxX - CGFloat(state.sidebarWidth) + 10, "right sidebar reserves space beside content")
        } else { check(false, "right sidebar reports content geometry") }
        state.tabLayout = .horizontal
        state.barAtBottom = true
        state.browserPreferences.collapseBarOnScroll = true
        await settle()
        if let header = LayoutChecks.frames["top-header"], let content = LayoutChecks.frames["content"] {
            check(header.minY >= content.maxY - 2, "bottom toolbar does not obscure content")
        } else { check(false, "bottom toolbar reports geometry") }
        state.barCondensed = true
        await settle()
        check(LayoutChecks.frames["top-header"].map { abs($0.height - 36) < 1 } == true, "reading ribbon has compact native height")
        state.barCondensed = false
        state.browserPreferences.collapseBarOnScroll = false
        state.barAtBottom = false
        for layout in [TabLayout.vertical, .horizontal] {
            state.tabLayout = layout
            for _ in 0..<2 {
                window.toggleFullScreen(nil); await settle()
                if let background = window.contentView as? WindowBackgroundView {
                    background.layoutSubtreeIfNeeded()
                    check(background.shell?.frame.height == background.bounds.height - background.shellTopInset, "fullscreen shell fits display")
                }
                window.toggleFullScreen(nil); await settle()
                if let background = window.contentView as? WindowBackgroundView {
                    background.layoutSubtreeIfNeeded()
                    check(background.shell?.frame == background.bounds, "fullscreen exit has no residual padding")
                }
            }
        }
        print("IKTEST featurebatchchecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }
}
#endif
