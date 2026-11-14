#if DEBUG
import AppKit

/// Several regular windows (`BrowserWindows`): moving a tab keeps its live page, settings and bookmarks are shared,
/// the session saves every window, tearing off, dropping into another window, and closing the first window.
@MainActor
enum WindowChecks {
    static func run(_ browser: BrowserWindowController) async {
        let state = browser.state
        var failures = 0
        func check(_ value: Bool, _ title: String) {
            print("IKTEST windows \(value ? "PASS" : "FAIL") \(title)")
            if !value { failures += 1 }
        }
        func settle(_ ms: Int = 400) async { try? await Task.sleep(for: .milliseconds(ms)) }
        browser.window?.makeKeyAndOrderFront(nil)
        guard let first = state.newTab(url: "https://example.com/one"), let second = state.newTab(url: "https://example.com/two") else {
            check(false, "opens two tabs")
            return finish(failures)
        }
        await settle(700)
        let page = browser.content.controller(for: second.id)?.page
        check(page != nil, "the tab has a live page before moving")

        // Move Tab to New Window.
        browser.moveToNewWindow(second.id)
        await settle()
        guard let other = BrowserWindows.others.last else {
            check(false, "Move Tab to New Window opens a window")
            return finish(failures)
        }
        check(other.window?.isVisible == true, "the new window is on screen")
        check(state.tab(second.id) == nil && other.state.tab(second.id) != nil, "the tab left its window for the new one")
        check(other.state.activeTabID == second.id, "the moved tab is selected in the new window")
        check(page != nil && other.content.controller(for: second.id)?.page === page, "the moved tab keeps its live page")
        check(page?.contentView.window === other.window, "the page now shows in the new window")
        check(browser.content.controller(for: second.id) == nil, "the old window let go of the tab's controller")
        check(state.closed.first?.id != second.id, "moving is not closing (nothing added to recently closed)")

        // Shared settings and bookmarks, both ways.
        let mode = state.colorMode, glass = state.useGlass
        state.colorMode = mode == .dark ? .light : .dark
        other.state.useGlass.toggle()
        state.addBookmark(first)
        await settle(200)
        check(other.state.colorMode == state.colorMode, "appearance set in one window applies to the other")
        check(state.useGlass == other.state.useGlass, "a setting changed in the second window reaches the first")
        check(other.state.bookmarks.contains { $0.url == first.url }, "bookmarks are shared")
        state.colorMode = mode; state.useGlass = glass
        await settle(200)
        check(other.state.colorMode == mode && other.state.useGlass == glass, "settings settle back in every window")

        // The session saves the second window with its tab.
        let saved = state.snapshot().windows
        check(saved?.count == 1 && saved?.first?.tabs.contains { $0.id == second.id } == true, "the session saves the other window's tabs")
        check(saved?.first?.isValid(besides: Set(state.tabs.map(\.id))) == true, "the saved window validates for restoring")
        check(!state.snapshot().tabs.contains { $0.id == second.id }, "the first window's own tabs don't include it")

        // Dropping the tab on the first window brings it back; the emptied window closes.
        TabDrag.load(TabDrag.provider(second.id), into: state) { _ in }
        await settle(600)
        check(state.tab(second.id) != nil && state.activeTabID == second.id, "a tab dropped on another window moves there")
        check(browser.content.controller(for: second.id)?.page === page, "and keeps its live page")
        check(BrowserWindows.others.isEmpty, "a window left without tabs closes")

        // Tearing off: dropped outside every window, the tab gets a window under the pointer.
        let screen = browser.window?.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        let point = NSPoint(x: screen.minX + 300, y: screen.maxY - 120)
        BrowserWindows.tearOff(second.id, from: browser, at: point)
        await settle()
        if let torn = BrowserWindows.others.last {
            check(torn.state.tab(second.id) != nil, "a tab dragged out of the windows opens in a new window")
            check(torn.window.map { $0.frame.contains(NSPoint(x: point.x, y: point.y - 10)) } == true, "the new window opens under the pointer")
            check(torn.content.controller(for: second.id)?.page === page, "the torn-off tab keeps its live page")
            // Closing the first window while another is open: the first takes over the other window's tabs and place.
            let place = torn.window?.frame
            browser.window?.performClose(nil)
            await settle(600)
            check(browser.window?.isVisible == true && !state.isFrozen, "closing the first window keeps the session's owner open")
            check(BrowserWindows.others.isEmpty, "the other window went in its place")
            check(state.tab(second.id) != nil && state.tab(first.id) == nil, "it shows the other window's tabs")
            check(browser.content.controller(for: second.id)?.page === page, "with their live pages")
            check(browser.window?.frame == place, "where the other window was")
            check(state.closed.contains { $0.id == first.id }, "its own tabs can be reopened with ⌘⇧T")
        } else {
            check(false, "tearing off opens a window")
        }

        // A closed second window's tabs join recently closed.
        _ = state.newTab(url: "https://example.com/three")
        await settle()
        if let active = state.activeTabID { browser.moveToNewWindow(active) }
        await settle()
        let movedID = BrowserWindows.others.last?.state.activeTabID
        BrowserWindows.others.last?.window?.close()
        await settle()
        check(BrowserWindows.others.isEmpty && state.closed.first?.id == movedID, "closing another window lists its tabs as recently closed")
        check(state.snapshot().windows == nil, "a closed window leaves the session")
        finish(failures)
    }

    private static func finish(_ failures: Int) {
        print("IKTEST windowchecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }
}
#endif
