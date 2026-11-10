#if DEBUG
import Foundation

/// Cross-site isolation on WebKit: a site (localhost) sets cookies and local storage as a top-level page,
/// then another site (127.0.0.1) frames it. The frame must see neither, with the setting on; storage stays
/// partitioned either way. Prints what the frame saw with the setting off, which WebKit decides itself.
@MainActor
enum CookieIsolationChecks {
    static func run(_ browser: BrowserWindowController, base: String, check: (Bool, String) -> Void) async {
        let state = browser.state, remote = base.replacingOccurrences(of: "127.0.0.1", with: "localhost")
        browser.open(remote + "/cookie-set", inNewTab: true)
        try? await Task.sleep(for: .milliseconds(900))
        let firstParty = try? await browser.activeController?.page?.callAsync("return document.cookie") as? String
        check(firstParty?.contains("ikago_none=1") == true, "the fixture site keeps its own cookies as a top-level page (\(firstParty ?? "none"))")

        browser.open(base + "/", inNewTab: true)
        try? await Task.sleep(for: .milliseconds(700))
        guard let page = browser.activeController?.page else { return check(false, "cross-site fixture page exists") }
        func framed() async -> [String: Any]? {
            try? await page.callAsync("""
                return await new Promise(resolve => {
                  const frame = document.createElement('iframe')
                  addEventListener('message', event => { if (event.data && event.data.ikagoCookies) { frame.remove(); resolve(event.data) } })
                  frame.src = '\(remote)/cookie-echo?' + Math.random()
                  document.body.append(frame)
                  setTimeout(() => resolve(null), 4000)
                })
                """) as? [String: Any]
        }
        func describe(_ seen: [String: Any]?) -> String {
            guard let seen else { return "no answer" }
            return "header=\(seen["header"] ?? "") cookie=\(seen["cookie"] ?? "") storage=\(seen["storage"] ?? "null")"
        }
        let blocked = await framed()
        check(blocked != nil && (blocked?["header"] as? String ?? "x").isEmpty && (blocked?["cookie"] as? String ?? "x").isEmpty,
              "a framed site gets none of its cookies under another site (\(describe(blocked)))")
        check(blocked != nil && !(blocked?["storage"] is String), "a framed site's local storage is partitioned per top-level site")

        state.browserPreferences.blockThirdPartyCookies = false
        BrowserSecurity.shared.apply(state.browserPreferences)
        let allowed = await framed()
        print("IKTEST security INFO third-party cookies setting off: \(describe(allowed))")
        check(allowed != nil && !(allowed?["storage"] is String), "local storage stays partitioned with the cookie setting off")
        state.browserPreferences.blockThirdPartyCookies = nil
        BrowserSecurity.shared.apply(state.browserPreferences)
    }
}
#endif
