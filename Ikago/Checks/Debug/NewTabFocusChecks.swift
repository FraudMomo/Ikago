#if DEBUG
import AppKit
import WebKit

@MainActor
enum NewTabFocusChecks {
    static func run(_ browser: BrowserWindowController, base: String) async {
        guard WebProfiles.isTestMode, URL(string: base)?.host == "127.0.0.1" else {
            print("IKTEST newtabfocuschecks FAIL requires isolated profile and loopback fixture"); return
        }
        var failures = 0
        func check(_ value: Bool, _ name: String) {
            print("IKTEST newtabfocus \(value ? "PASS" : "FAIL") \(name)")
            if !value { failures += 1 }
        }
        NSApp.activate()
        browser.window?.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: .milliseconds(200))
        let state = browser.state, manager = ExtensionManager.shared
        let initialIDs = Set(state.tabs.map(\.id)), previous = state.activeTabID
        let original = (state.newTabMode, state.homepage, state.newTabExtensionID, state.focusAddressBarOnNewTab,
                        state.tabLayout, state.addressStyle, state.sidebarVisible, state.chromeLayout)
        let root = FileManager.default.temporaryDirectory.appending(path: "IkagoNewTabFocus-\(UUID().uuidString)")
        let id = "mmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmm"
        defer {
            browser.palette.onDismiss()
            for tab in state.tabs where !initialIDs.contains(tab.id) { state.closeTab(tab.id, removingPin: true) }
            manager.remove(id)
            state.newTabMode = original.0; state.homepage = original.1; state.newTabExtensionID = original.2
            state.focusAddressBarOnNewTab = original.3; state.tabLayout = original.4; state.addressStyle = original.5
            state.sidebarVisible = original.6; state.chromeLayout = original.7
            if let previous { state.select(previous) }
            try? FileManager.default.removeItem(at: root)
        }
        do {
            let package = root.appending(path: "Extension")
            try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
            let manifest: [String: Any] = ["manifest_version": 3, "name": "New tab focus fixture", "version": "1.0",
                                          "chrome_url_overrides": ["newtab": "newtab.html"]]
            try JSONSerialization.data(withJSONObject: manifest).write(to: package.appending(path: "manifest.json"))
            try Data("<!doctype html><title>New tab focus fixture</title><input id='site-focus' autofocus><script src='focus.js'></script>".utf8)
                .write(to: package.appending(path: "newtab.html"))
            try Data("addEventListener('load', () => setTimeout(() => document.getElementById('site-focus').focus(), 100));".utf8)
                .write(to: package.appending(path: "focus.js"))
            _ = try await manager.install(unpackedAt: package, id: id, fromWebStore: false, approve: false)
            guard manager.contexts[id]?.overrideNewTabPageURL != nil else { throw ExtensionManager.error("Missing fixture new-tab page") }
            state.homepage = base + "/focus.html"
            state.newTabExtensionID = id
            state.sidebarVisible = true
            state.chromeLayout = ChromeLayout()
            for layout in TabLayout.allCases {
                state.tabLayout = layout
                for style in AddressStyle.allCases {
                    // Settings cannot change address styles while the command overlay is open.
                    // Settle its dismissal before configuring the next independent UI case.
                    browser.palette.onDismiss()
                    try? await Task.sleep(for: .milliseconds(300))
                    state.addressStyle = style
                    for mode in [NewTabMode.homepage, .extensionPage] {
                        browser.palette.onDismiss()
                        state.newTabMode = mode
                        state.focusAddressBarOnNewTab = true
                        let count = state.tabs.count
                        browser.newTab()
                        let loaded = await waitForPage(browser)
                        check(loaded && state.tabs.count == count + 1,
                              "\(layout.rawValue)/\(style.rawValue)/\(mode.rawValue) opens exactly one provider tab")
                        if !addressHasFocus(browser) { dumpFocus(browser) }
                        check(browser.isEditingAddress && browser.chrome.editingTabID == state.activeTabID && addressHasFocus(browser),
                              "\(layout.rawValue)/\(style.rawValue)/\(mode.rawValue) gives the keyboard to the address field")
                        check(browser.palette.query.isEmpty && browser.palette.mode == .currentTab && !browser.content.shouldFocusPage(),
                              "new address input is ready to type and targets the opened page")
                        let input = try? await browser.activeController?.page?.callAsync("return document.activeElement?.id")
                        check(input as? String == "site-focus" && addressHasFocus(browser), "provider autofocus cannot take typing away from the address field")
                    }
                }
            }
            browser.palette.onDismiss()
            state.tabLayout = .vertical; state.addressStyle = .integrated; state.sidebarVisible = false
            browser.newTab()
            _ = await waitForPage(browser)
            check(browser.chrome.showPalette && addressHasFocus(browser), "collapsed sidebar uses a visible floating address field")
            browser.palette.onDismiss()
            state.sidebarVisible = true; state.chromeLayout.sidebarShowsAddress = false
            browser.newTab()
            _ = await waitForPage(browser)
            check(browser.chrome.showPalette && addressHasFocus(browser), "hidden sidebar address control uses the floating field")
            if let field = browser.window?.contentView?.firstDescendant(of: FocusingTextField.self), let editor = field.currentEditor() as? NSTextView {
                editor.insertText("unfinished", replacementRange: NSRange(location: NSNotFound, length: 0))
            }
            state.newTabMode = .homepage
            browser.newTab()
            _ = await waitForPage(browser)
            check(browser.palette.query.isEmpty && addressHasFocus(browser), "creating another tab while typing starts a fresh focused address")
            browser.palette.onDismiss()
            state.chromeLayout = ChromeLayout(); state.focusAddressBarOnNewTab = false
            for mode in [NewTabMode.homepage, .extensionPage] {
                state.newTabMode = mode
                browser.newTab()
                _ = await waitForPage(browser)
                check(!browser.isEditingAddress && !addressHasFocus(browser), "toggle off preserves \(mode.rawValue) page focus")
            }
            state.newTabMode = .commandBar
            browser.newTab()
            try? await Task.sleep(for: .milliseconds(300))
            check(browser.isEditingAddress && addressHasFocus(browser), "command-bar mode remains ready for typing with toggle off")
            let store = SessionStore(directory: root.appending(path: "Preferences"))
            let preferences = BrowserState(store: store)
            preferences.focusAddressBarOnNewTab = true; preferences.saveNow()
            check(BrowserState(store: store).focusAddressBarOnNewTab, "focus preference survives session restore")
            var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(preferences.snapshot())) as! [String: Any]
            var settings = json["newTab"] as! [String: Any]; settings.removeValue(forKey: "focusAddressBar"); json["newTab"] = settings
            try store.save(JSONDecoder().decode(Session.self, from: JSONSerialization.data(withJSONObject: json)))
            check(!BrowserState(store: store).focusAddressBarOnNewTab, "older sessions keep the existing focus behavior")
        } catch { check(false, error.localizedDescription) }
        print("IKTEST newtabfocuschecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }

    private static func dumpFocus(_ browser: BrowserWindowController) {
        print("IKTEST focus responder=\(String(describing: browser.window?.firstResponder)) key=\(browser.window?.isKeyWindow == true) appActive=\(NSApp.isActive) inline=\(browser.chrome.inlineAddress) palette=\(browser.chrome.showPalette) targetMatches=\(browser.chrome.editingTabID == browser.state.activeTabID)")
        func inspect(_ view: NSView) {
            if let field = view as? FocusingTextField {
                let rect = field.convert(field.bounds, to: browser.window?.contentView)
                print("IKTEST focus field hidden=\(field.isHiddenOrHasHiddenAncestor) rect=\(rect) editor=\(String(describing: field.currentEditor()))")
            }
            view.subviews.forEach(inspect)
        }
        if let root = browser.window?.contentView { inspect(root) }
    }

    private static func addressHasFocus(_ browser: BrowserWindowController) -> Bool {
        guard let window = browser.window, let root = window.contentView else { return false }
        func find(_ view: NSView) -> Bool {
            if let field = view as? FocusingTextField, !field.isHiddenOrHasHiddenAncestor,
               window.firstResponder === field || field.currentEditor().map({ window.firstResponder === $0 }) == true { return true }
            return view.subviews.contains(where: find)
        }
        return find(root)
    }
    private static func waitForPage(_ browser: BrowserWindowController) async -> Bool {
        for _ in 0..<250 {
            if browser.state.activeTab?.title == "New tab focus fixture", browser.state.activeTab?.isLoading == false {
                try? await Task.sleep(for: .milliseconds(400))
                return true
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return false
    }
}
#endif
