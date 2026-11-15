#if DEBUG
import AppKit
import WebKit

/// The sign-in key: which fields show it, that only a trusted click reaches native code, and
/// that the Settings switch hides it. Apple's panel itself is not opened (it takes focus).
@MainActor
enum PasswordAutoFillChecks {
    static func run(_ browser: BrowserWindowController, base: String) async {
        guard WebProfiles.isTestMode, URL(string: base)?.host == "127.0.0.1" else { return }
        var failures = 0
        func check(_ value: Bool, _ title: String) {
            print("IKTEST passwords \(value ? "PASS" : "FAIL") \(title)")
            if !value { failures += 1 }
        }
        let state = browser.state, autofill = PasswordAutoFill.shared
        let originalTabs = Set(state.tabs.map(\.id)), originalActive = state.activeTabID
        defer {
            try? PasswordVault.shared.deleteAll()
            state.browserPreferences.passwordSource = nil
            state.browserPreferences.passwordAutoFill = nil
            BrowserSecurity.shared.apply(state.browserPreferences)
            for tab in state.tabs where !originalTabs.contains(tab.id) { state.closeTab(tab.id, removingPin: true) }
            if let originalActive { state.select(originalActive) }
        }
        check(BrowserPreferences().passwordAutoFill ?? true, "filling from Apple Passwords defaults on")
        check(SystemPasswordPanel.isAvailable, "AppKit's Edit ▸ AutoFill ▸ Passwords… item is present")
        NSApp.activate(); browser.window?.makeKeyAndOrderFront(nil)
        browser.open(base + "/login.html", inNewTab: true)
        for _ in 0..<250 {
            if state.activeTab?.title == "Login fixture" && state.activeTab?.isLoading == false { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        guard let page = browser.activeController?.page else { check(false, "fixture loaded"); return }
        page.focus()

        func key(after id: String) async -> [String: Any] {
            let rect = (try? await page.callAsync("const r = document.getElementById('\(id)').getBoundingClientRect(); return {x: r.x + 20, y: r.y + r.height / 2}")) as? [String: Double]
            if let x = rect?["x"], let y = rect?["y"] { click(x: x, y: y, page: page) }
            try? await Task.sleep(for: .milliseconds(300))
            return (try? await page.callAsync("return window.__ikagoPasswordKey.state()")) as? [String: Any] ?? [:]
        }
        for id in ["password", "username", "identifier"] {
            let shown = await key(after: id)
            check(shown["visible"] as? Bool == true && shown["field"] as? String == id, "key shows in the \(id) field")
        }
        for id in ["search", "newsletter-name"] {
            check(await key(after: id)["visible"] as? Bool == false, "no key in the \(id) field")
        }

        let shown = await key(after: "password"), before = autofill.testRequests
        _ = try? await page.callAsync("window.__ikagoPasswordKey.click(); return true")
        try? await Task.sleep(for: .milliseconds(200))
        check(autofill.testRequests == before, "a scripted click never opens the panel")
        if let x = shown["x"] as? Double, let y = shown["y"] as? Double { click(x: x, y: y, page: page) }
        try? await Task.sleep(for: .milliseconds(300))
        check(autofill.testRequests == before + 1, "a trusted click on the key asks for Apple's panel")
        let focused = try? await page.callAsync("return document.activeElement.id")
        check(focused as? String == "password", "the field keeps focus for Apple's panel to fill")

        // Ikago's own vault: no key without a saved login, then a trusted click fills it (checks pick the first login).
        state.browserPreferences.passwordSource = PasswordSource.ikago.rawValue
        BrowserSecurity.shared.apply(state.browserPreferences)
        _ = await key(after: "search")
        check(await key(after: "password")["visible"] as? Bool == false, "Ikago Passwords shows no key on a site without saved logins")
        _ = try? PasswordVault.shared.add([.init(url: base, title: nil, username: "vault-user", password: "vault pass \"1\"")])
        _ = await key(after: "search")
        let vaultKey = await key(after: "password")
        check(vaultKey["visible"] as? Bool == true, "Ikago Passwords shows the key on a site with a saved login")
        let panelRequests = autofill.testRequests
        if let x = vaultKey["x"] as? Double, let y = vaultKey["y"] as? Double { click(x: x, y: y, page: page) }
        var filled: [String: String] = [:]
        for _ in 0..<50 {
            try? await Task.sleep(for: .milliseconds(100))
            filled = (try? await page.callAsync("return {u: document.getElementById('username').value, p: document.getElementById('password').value}")) as? [String: String] ?? [:]
            if filled["p"]?.isEmpty == false { break }
        }
        check(filled["u"] == "vault-user" && filled["p"] == "vault pass \"1\"", "a trusted click fills the saved username and password \(filled)")
        check(autofill.testRequests == panelRequests, "Ikago Passwords never opens Apple's panel")
        _ = try? await page.callAsync("document.getElementById('username').value = ''; document.getElementById('password').value = ''; return true")
        _ = try? await page.callAsync("window.__ikagoPasswordKey.click(); return true")
        try? await Task.sleep(for: .milliseconds(500))
        let scripted = try? await page.callAsync("return document.getElementById('password').value")
        check(scripted as? String == "", "a scripted click never fills a password")
        let elsewhere = try? await page.callAsync("return window.__ikagoPasswordKey.fill('u', 'p', 'https://other.test')")
        let afterElsewhere = try? await page.callAsync("return document.getElementById('password').value")
        check(elsewhere as? Bool == false && afterElsewhere as? String == "", "a login unlocked for another origin never fills this page")
        state.browserPreferences.passwordSource = nil
        try? PasswordVault.shared.deleteAll()

        state.browserPreferences.passwordAutoFill = false
        BrowserSecurity.shared.apply(state.browserPreferences)
        _ = await key(after: "search")  // the switch applies from the next focus
        check(await key(after: "password")["visible"] as? Bool == false, "the Settings switch hides the key")
        print("IKTEST passwordautofillchecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }

    /// A real mouse click delivered to this app's web view (no global input is posted).
    private static func click(x: Double, y: Double, page: WebTab) {
        let view = page.webView
        guard let window = view.window else { return }
        let location = view.convert(NSPoint(x: x, y: view.isFlipped ? y : view.bounds.height - y), to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                 windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1) else { continue }
            type == .leftMouseDown ? view.mouseDown(with: event) : view.mouseUp(with: event)
        }
    }
}
#endif
