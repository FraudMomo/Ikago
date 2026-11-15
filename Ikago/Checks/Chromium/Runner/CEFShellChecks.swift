import AppKit

/// Exercises real hidden SwiftUI/AppKit windows and embedded pages without taking focus.
@MainActor
enum CEFShellChecks {
    static func run(url: String) async throws {
        let state = BrowserState()
        for tab in Array(state.tabs) { state.closeTab(tab.id) }
        let first = state.newTab(url: url)!
        let shell = BrowserWindowController(state: state)
        defer { state.freezeForShutdown(); shell.content.shutdown() }
        guard shell.window?.frameAutosaveName.isEmpty == true else { throw CEFError.script("A disposable shell enabled production window autosave.") }
        try await wait {
            guard let page = shell.activeController?.page as? CEFWebTab else { return false }
            return page.page.ready && page.currentURL == url && !page.isLoading
        }
        guard let original = shell.activeController?.page else { throw CEFError.noResult }
        _ = try await original.evaluate("window.fixtureLayoutIdentity = 'retained'")
        if let chromium = original as? CEFWebTab { try await CEFPageStateChecks.run(chromium) }
        for topTabs in [false, true] {
            state.browserPreferences.sidebarTopTabs = topTabs ? true : nil
            try await settle(shell)
            guard shell.activeController?.page === original,
                  try await original.evaluate("window.fixtureLayoutIdentity") as? String == "retained" else {
                throw CEFError.script("A layout switch replaced the page or its isolated world.")
            }
            try CEFPageGrabChecks.run(shell)
        }
        // Switching back during the outgoing layout's animation must keep the page in the window.
        state.browserPreferences.sidebarTopTabs = nil
        try await settle(shell)
        state.browserPreferences.sidebarTopTabs = true
        try await Task.sleep(for: .milliseconds(50))
        state.browserPreferences.sidebarTopTabs = nil
        try await Task.sleep(for: .milliseconds(50))
        state.browserPreferences.sidebarTopTabs = true
        try await Task.sleep(for: .milliseconds(800))
        guard original.contentView.window === shell.window, original.contentView.bounds.width > 0 else {
            throw CEFError.script("A rapid layout switch removed the page from the window.")
        }
        try CEFPageGrabChecks.run(shell)
        let second = state.newTab(url: url, select: false)!
        let third = state.newTab(url: url, select: false)!
        state.select(first.id)
        state.splitWithDropped(second.id, edge: .right)
        state.splitWithDropped(third.id, edge: .bottom)
        for topTabs in [false, true] {
            state.browserPreferences.sidebarTopTabs = topTabs ? true : nil
            try await settle(shell)
            try await wait { state.visibleTabIDs.allSatisfy { shell.content.controller(for: $0)?.page?.isLoading == false } }
            guard state.visibleTabIDs.count == 3, state.splitLayout == .grid else { throw CEFError.script("Three-pane grid membership changed.") }
            for id in state.visibleTabIDs {
                guard let view = shell.content.controller(for: id)?.page?.contentView,
                      view.window === shell.window, view.bounds.width > 0, view.bounds.height > 0 else {
                    let view = shell.content.controller(for: id)?.page?.contentView
                    throw CEFError.script("A split pane lost its native view or viewport (tabRow=\(topTabs) view=\(view != nil) "
                        + "inWindow=\(view?.window === shell.window) size=\(view.map { NSStringFromSize($0.bounds.size) } ?? "-")).")
                }
            }
        }
        state.unsplit()
        var decoded: String?
        TabDrag.load(TabDrag.provider(first.id), into: nil) { decoded = $0 }
        try await wait { decoded != nil }
        guard decoded == first.id else { throw CEFError.script("Tab drag payload did not survive asynchronous transfer.") }
        state.move(first.id, before: third.id, pinned: false)
        state.select(first.id)
        try await settle(shell)
        guard shell.activeController?.page === original else { throw CEFError.script("Reordering recreated a page.") }
        try await CEFWindowMoveChecks.run(shell, tab: first.id, page: original)
        if let chromium = original as? CEFWebTab {
            try await CEFPictureInPictureChecks.run(shell, page: chromium)
            try await CEFTabSwitchChecks.run(shell, page: chromium, tab: first.id, other: third.id)
            try await CEFHistoryChecks.run(shell, url: url)
            try await CEFNewTabLinkChecks.run(shell, from: first.id, url: url)
            try await CEFNewTabLinkChecks.runBlankTarget(shell, from: first.id, url: url)
            try await CEFPeekKeepChecks.run(shell, from: first.id, url: url)
            state.select(first.id)
        }
        state.select(first.id)
        try await settle(shell)
        guard let nativeResponder = focusable(in: original.contentView),
              shell.window?.makeFirstResponder(nativeResponder) == true else {
            throw CEFError.script("CEF focus positive control failed.")
        }
        guard try CEFShortcutChecks.dispatch("l", shell: shell) else { throw CEFError.script("Open Location key equivalent was not handled.") }
        guard shell.isEditingAddress else { throw CEFError.script("Open Location did not start address editing.") }
        guard shell.window?.makeFirstResponder(nativeResponder) == false else {
            throw CEFError.script("A CEF page stole focus while the address was being edited.")
        }
        shell.dismissCommandPalette()
        guard try CEFShortcutChecks.dispatch("w", shell: shell) else { throw CEFError.script("Close Tab key equivalent was not handled.") }
        guard state.tab(first.id) == nil else { throw CEFError.script("Close Tab command failed.") }
        guard try CEFShortcutChecks.dispatch("t", modifiers: [.command, .shift], shell: shell) else { throw CEFError.script("Reopen key equivalent was not handled.") }
        guard state.tabs.contains(where: { $0.url == url }), state.tabs.count == 3 else { throw CEFError.script("Reopen Closed Tab command failed.") }
        try CEFShortcutChecks.editingKeysStayWithPage(shell)
        let secondState = BrowserState(store: SessionStore(directory: CEFSessions.root.appending(path: "SecondShell")))
        for tab in Array(secondState.tabs) { secondState.closeTab(tab.id) }
        secondState.newTab(url: url)
        let secondShell = BrowserWindowController(state: secondState)
        defer { secondState.freezeForShutdown(); secondShell.content.shutdown() }
        try await wait {
            guard let page = secondShell.activeController?.page as? CEFWebTab else { return false }
            // SwiftUI attaches the host on its first layout pass, which a fast load can beat.
            return page.page.ready && page.currentURL == url && !page.isLoading && page.contentView.window === secondShell.window
        }
        guard secondShell.activeController?.page !== shell.activeController?.page else {
            throw CEFError.script("Two windows shared a native page owner.")
        }
        try migratesChromeLayoutSession(from: state)
        state.browserPreferences.preferredEngine = .webkit
        guard shell.activeController?.page is CEFWebTab else { throw CEFError.script("Engine preferences replaced a live page.") }
        print("CEF_SHELL_OK layouts rapid-layout-switch chrome-session-migration page-identity three-pane-grid drag-payload reorder window-move picture-in-picture restored-history address close-reopen multiwindow")
    }
    /// A session saved with a retired top-tab layout (Chrome, Top Bar) restores as Sidebar + Tabs.
    private static func migratesChromeLayoutSession(from state: BrowserState) throws {
        var saved = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state.snapshot())) as! [String: Any]
        var controls = saved["chrome"] as? [String: Any] ?? [:]
        saved["layout"] = "chrome"
        // Without the new preference, so only the layout migration can turn the tab row on.
        if var browser = saved["browser"] as? [String: Any] { browser.removeValue(forKey: "sidebarTopTabs"); saved["browser"] = browser }
        controls["topBarTrailing"] = ["share", "tabSearch", "extensions"]
        controls["chromeLeading"] = ["back"]
        saved["chrome"] = controls
        let session = try JSONDecoder().decode(Session.self, from: JSONSerialization.data(withJSONObject: saved))
        let store = SessionStore(directory: CEFSessions.root.appending(path: "MigrationShell"))
        try store.save(session)
        let restored = BrowserState(store: store)
        defer { restored.freezeForShutdown() }
        guard restored.browserPreferences.sidebarTopTabs == true, restored.chromeLayout.sidebarTop == state.chromeLayout.sidebarTop else {
            throw CEFError.script("A Chrome layout session did not migrate.")
        }
    }
    private static func settle(_ shell: BrowserWindowController) async throws {
        try await Task.sleep(for: .milliseconds(250))
        shell.window?.contentView?.layoutSubtreeIfNeeded()
    }
    private static func focusable(in view: NSView) -> NSView? {
        if view.acceptsFirstResponder { return view }
        for child in view.subviews { if let found = focusable(in: child) { return found } }
        return nil
    }
    private static func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<200 { if condition() { return }; try await Task.sleep(for: .milliseconds(50)) }
        throw CEFError.script("Native shell fixture timed out.")
    }
}
