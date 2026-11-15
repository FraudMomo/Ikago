import AppKit
import IKCEFBridge

/// Cross-site isolation on Chromium, in the disposable smoke profile: localhost sets cookies and local
/// storage as a top-level page, then 127.0.0.1 frames it. With third-party cookies blocked the frame gets
/// none; local storage is partitioned per top-level site either way. The allowed mode is the control
/// that shows the fixture can see cookies at all.
@MainActor
enum CEFCookieIsolationChecks {
    static func run(url: String, window: NSWindow) async throws {
        print("CEF_SMOKE_STAGE cookie-isolation")
        let profile = "Smoke"
        let previous = IKCEFSecurity.snapshot(forProfile: profile)["cookieControlsMode"] as? Int ?? 1
        defer { try? IKCEFSecurity.setPreference("profile.cookie_controls_mode", value: previous, profile: profile) }
        let tab = try CEFWebTab(profileID: profile)
        defer { tab.tearDown() }
        let content = window.contentView
        window.contentView = tab.page
        defer { window.contentView = content }
        try await wait { tab.page.ready }
        let remote = url.replacingOccurrences(of: "127.0.0.1", with: "localhost")

        func load(_ address: String) async throws {
            let before = tab.documentGeneration
            tab.load(address)
            try await wait { tab.documentGeneration >= before + 2 && !tab.page.loading }
        }
        func framed() async throws -> [String: Any] {
            let result = try await CEFSmoke.method(tab.page, "Runtime.evaluate", ["expression": """
                new Promise(resolve => {
                  const frame = document.createElement('iframe')
                  addEventListener('message', event => { if (event.data && event.data.ikagoCookies) { frame.remove(); resolve(event.data) } })
                  frame.src = '\(remote)cookie-echo?' + Math.random()
                  document.body.append(frame)
                  setTimeout(() => resolve(null), 4000)
                })
                """, "awaitPromise": true, "returnByValue": true])
            guard let value = (result["result"] as? [String: Any])?["value"] as? [String: Any] else {
                throw CEFError.script("The cross-site frame didn't answer.")
            }
            return value
        }
        func cookies(_ seen: [String: Any]) -> String { "\(seen["header"] as? String ?? "")|\(seen["cookie"] as? String ?? "")" }

        try await load(remote + "cookie-set")
        try IKCEFSecurity.setPreference("profile.cookie_controls_mode", value: 1, profile: profile)
        try await load(url)
        let blocked = try await framed()
        print("CEF_COOKIE_ISOLATION blocked-mode \(cookies(blocked))")
        guard cookies(blocked) == "|" else { throw CEFError.script("A framed site got its cookies with third-party cookies blocked: \(blocked)") }
        guard !(blocked["storage"] is String) else { throw CEFError.script("A framed site's local storage wasn't partitioned.") }

        try IKCEFSecurity.setPreference("profile.cookie_controls_mode", value: 0, profile: profile)
        try await load(url)
        let allowed = try await framed()
        print("CEF_COOKIE_ISOLATION allowed-mode \(cookies(allowed)) storage=\(allowed["storage"] ?? "null")")
        guard !(allowed["storage"] is String) else { throw CEFError.script("Local storage wasn't partitioned with third-party cookies allowed.") }
        print("CEF_COOKIE_ISOLATION_OK blocked-no-cookies storage-partitioned")
    }

    private static func wait(_ predicate: @MainActor () async -> Bool) async throws {
        for _ in 0..<200 {
            if await predicate() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw CEFError.script("The cookie isolation fixture timed out.")
    }
}
