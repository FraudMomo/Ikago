import AppKit
import IKCEFBridge

/// The password key on Chromium, in the disposable smoke profile with a test vault key: nothing is injected
/// without a saved login, the page can't see the script, a click the page
/// makes doesn't fill, and a real click on the key does.
@MainActor
enum CEFPasswordChecks {
    static func run(url: String, window: NSWindow) async throws {
        print("CEF_SMOKE_STAGE passwords")
        guard SealedStorage.usesTestKey else { throw CEFError.script("Password checks need the test vault key.") }
        let vault = PasswordVault.shared
        try? vault.deleteAll()
        defer { try? vault.deleteAll() }
        let tab = try CEFWebTab(profileID: "Smoke")
        defer { tab.tearDown() }
        let previous = window.contentView
        window.contentView = tab.page
        defer { window.contentView = previous }
        try await wait { tab.page.ready }

        func load() async throws {
            let before = tab.documentGeneration
            tab.load(url)
            try await wait { tab.documentGeneration >= before + 2 && !tab.page.loading && (tab.hasPasswordKey || !PasswordChooser.offers(for: URL(string: url))) }
            _ = try await CEFSmoke.method(tab.page, "Runtime.evaluate", ["expression": """
                document.body.insertAdjacentHTML('beforeend', '<form style="margin:40px"><input id="user" name="username" autocomplete="username" style="display:block;width:240px;height:28px"><input id="pass" type="password" style="display:block;width:240px;height:28px"></form>'); true
                """])
        }
        func page(_ expression: String) async throws -> Any? {
            let result = try await CEFSmoke.method(tab.page, "Runtime.evaluate", ["expression": expression, "returnByValue": true])
            return (result["result"] as? [String: Any])?["value"]
        }
        func click(_ expression: String) async throws {
            guard let point = try await page("(() => { const r = \(expression).getBoundingClientRect(); return [r.x + r.width - 6, r.y + r.height / 2] })()") as? [Double],
                  point.count == 2 else { throw CEFError.script("Password fixture element is missing.") }
            for type in ["mousePressed", "mouseReleased"] {
                _ = try await CEFSmoke.method(tab.page, "Input.dispatchMouseEvent", ["type": type, "x": point[0], "y": point[1], "button": "left", "clickCount": 1])
            }
        }
        func keyVisible() async throws -> Bool {
            try await page("(() => { const k = document.querySelector('ikago-password-key'); return !!k && k.style.getPropertyValue('display') === 'block' })()") as? Bool == true
        }

        tab.focus()
        try await load()
        print("CEF_PASSWORDS_STAGE loaded")
        try await click("document.getElementById('pass')")
        try await Task.sleep(for: .milliseconds(600))
        guard !tab.hasPasswordKey, try await page("document.querySelector('ikago-password-key') === null") as? Bool == true
        else { throw CEFError.script("The password key was injected for a site with no saved login.") }
        print("CEF_PASSWORDS_STAGE no-key")
        _ = try vault.add([.init(url: url, title: nil, username: "cef-user", password: "cef pass 'quoted' \"too\"")])
        try await load()
        guard try await page("typeof window.__ikagoPasswordKey === 'undefined'") as? Bool == true
        else { throw CEFError.script("The page can see the password key's script.") }
        try await click("document.getElementById('pass')")
        try await wait { (try? await keyVisible()) == true }
        print("CEF_PASSWORDS_STAGE key-shown")
        // A click Ikago never saw (the page's own, or one sent through DevTools) doesn't fill.
        try await click("document.querySelector('ikago-password-key')")
        try await Task.sleep(for: .milliseconds(600))
        guard try await page("document.getElementById('pass').value") as? String == "" else {
            throw CEFError.script("A click Ikago didn't see filled the password.")
        }
        // A real click at the key, in the page view's coordinates.
        guard let center = try await page("(() => { const r = document.querySelector('ikago-password-key').getBoundingClientRect(); return [r.x + r.width / 2, r.y + r.height / 2] })()") as? [Double],
              center.count == 2 else { throw CEFError.script("The password key is missing.") }
        let zoom = pow(1.2, tab.zoomLevel)
        tab.passwordKeyClicked(at: NSPoint(x: center[0] * zoom, y: tab.page.bounds.height - tab.page.topInset - center[1] * zoom))
        try await wait {
            (try? await page("document.getElementById('pass').value")) as? String == "cef pass 'quoted' \"too\""
        }
        guard try await page("document.getElementById('user').value") as? String == "cef-user" else {
            throw CEFError.script("The username wasn't filled.")
        }
        print("CEF_PASSWORDS_OK no-login-no-script script-hidden page-click-no-fill real-click-fills")
    }

    private static func wait(_ predicate: @MainActor () async -> Bool) async throws {
        for _ in 0..<200 {
            if await predicate() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw CEFError.script("The password fixture timed out.")
    }
}
