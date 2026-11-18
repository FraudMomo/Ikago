#if DEBUG
import AppKit
import CryptoKit

@MainActor
enum EssentialsChecks {
    static func run(_ browser: BrowserWindowController) async {
        let state = browser.state, original = state.snapshot()
        var failures = 0
        func check(_ value: Bool, _ title: String) {
            print("IKTEST essentials \(value ? "PASS" : "FAIL") \(title)")
            if !value { failures += 1 }
        }
        defer { state.apply(original) }
        let pin = state.newTab(url: "https://saved-pin.invalid")!
        state.togglePin(pin.id)
        let controller = browser.content.ensureController(for: pin)!
        controller.startIfNeeded()
        pin.faviconURL = URL(string: "https://icons.invalid/custom.png")
        browser.closeTab(pin.id)
        try? await Task.sleep(for: .milliseconds(400))
        check(state.tab(pin.id) != nil && pin.pinned && pin.isHibernating && controller.page == nil,
              "closing a pin retains its identity and unloads its web view")
        check(state.activeTabID != pin.id && !state.closed.contains { $0.id == pin.id }, "unloaded pin leaves active panes and closed-tab history")
        state.select(pin.id)
        try? await Task.sleep(for: .milliseconds(400))
        check(controller.page != nil && !pin.isHibernating, "selecting a pin wakes the same tab")
        browser.closeTab(pin.id)
        try? await Task.sleep(for: .milliseconds(300))
        let restored = BrowserState(store: SessionStore(directory: SessionStore.testDirectory.appending(path: "IconRestore")))
        defer { restored.saveTask?.cancel() }
        restored.apply(state.snapshot())
        check(restored.tab(pin.id)?.faviconURL == pin.faviconURL && restored.tab(pin.id)?.isHibernating == true,
              "custom favicon and unloaded state survive session round trip")
        let tab = state.newTab(url: "https://saved-icon.invalid")!
        tab.faviconURL = pin.faviconURL
        state.addBookmark(tab)
        check(state.tab(tab.id) != nil && state.bookmarks.first { $0.url == tab.url }?.favicon == pin.faviconURL?.absoluteString,
              "saving a bookmark preserves the open tab and custom icon")
        state.move(tab.id, before: nil, pinned: true)
        state.move(tab.id, before: nil, pinned: false)
        check(!tab.pinned && tab.faviconURL == pin.faviconURL, "dragging a pin into open tabs unpins it and retains its icon")
        // The tab menu's pin choices with essentials shown: a pinned row, an essential tile, and back.
        let savedGrid = state.browserPreferences.showPinnedGrid
        state.browserPreferences.showPinnedGrid = true
        let choice = state.newTab(url: "https://pin-choice.invalid")!
        state.movePin(choice.id, intoGrid: true)  // Add to Essentials, from an open tab
        check(choice.pinned && state.sidebarGridPinnedTabs.contains { $0.id == choice.id }, "Add to Essentials makes an open tab an essential tile")
        state.movePin(choice.id, intoGrid: false)  // Move to Pinned Tabs
        check(choice.pinned && choice.pinAsRow && !state.sidebarGridPinnedTabs.contains { $0.id == choice.id }
              && state.orderedSidebarTabs.contains { $0.id == choice.id }, "Move to Pinned Tabs makes it a pinned row in the list")
        state.movePin(choice.id, intoGrid: true)
        state.togglePin(choice.id)  // Remove from Essentials
        check(!choice.pinned && !state.sidebarGridPinnedTabs.contains { $0.id == choice.id }, "Remove from Essentials leaves an ordinary tab")
        state.togglePin(choice.id)  // Pin Tab
        check(choice.pinned && choice.pinAsRow, "Pin Tab still pins as a row while essentials show")
        // Top Tabs: pins sit in the tab row or in the rail, never both.
        let savedLayout = state.browserPreferences.sidebarTopTabs, savedVisible = state.sidebarVisible
        state.browserPreferences.sidebarTopTabs = true
        let savedPeek = state.browserPreferences.sidebarEdgePeek
        for (visible, peek) in [(true, true), (false, true), (true, false), (false, false)] {
            state.sidebarVisible = visible
            state.browserPreferences.sidebarEdgePeek = peek ? nil : false
            let label = "sidebar \(visible ? "shown" : "hidden"), edge peek \(peek ? "on" : "off")"
            check(state.pinsInTabRow != state.pinsInRail, "pins show once with the \(label)")
            // Essentials stay in the mini sidebar wherever it can appear; only a sidebar that can't appear sends them to the row.
            check(state.pinsInRail == (visible || peek), "essentials sit in the mini sidebar with the \(label) (rail \(state.pinsInRail))")
        }
        state.browserPreferences.sidebarEdgePeek = savedPeek
        state.browserPreferences.sidebarTopTabs = savedLayout; state.sidebarVisible = savedVisible
        state.browserPreferences.showPinnedGrid = savedGrid
        let iconURL = URL(string: "https://cached-icon.invalid/\(UUID()).png")!
        let key = SHA256.hash(data: Data(iconURL.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        let folder = SessionStore.testDirectory.appending(path: "Favicons")
        let file = folder.appending(path: key)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let image = NSImage(size: NSSize(width: 16, height: 16))
            image.lockFocus(); NSColor.red.setFill(); NSRect(x: 0, y: 0, width: 16, height: 16).fill(); image.unlockFocus()
            try image.tiffRepresentation!.write(to: file)
            try FileManager.default.setAttributes([.modificationDate: Date.distantPast], ofItemAtPath: file.path)
            let cached = await FaviconCache.shared.image(for: iconURL)
            check(cached != nil, "old disk icon loads offline without expiry or a live page")
        } catch { check(false, error.localizedDescription) }
        try? FileManager.default.removeItem(at: file)
        print("IKTEST essentialschecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }
}
#endif
