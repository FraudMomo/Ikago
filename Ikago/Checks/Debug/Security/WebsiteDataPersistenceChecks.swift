#if DEBUG
import WebKit

/// Cookies and localStorage survive a relaunch. Needs a disposable `IKAGO_TEST_STORAGE_UUID`
/// (the fixture store) and runs in two processes: `write|<base>` then `quit`, and
/// `read|<base>` in a fresh launch with the same UUID. `write` also opens a second store
/// object for the identifier, as a relaunch would.
@MainActor
enum WebsiteDataPersistenceChecks {
    static let cookieName = "ikagoPersist", cookieDomain = "persistence.ikago.test"

    static func run(_ browser: BrowserWindowController, arg: String) async {
        var failures = 0
        func check(_ value: Bool, _ title: String) {
            print("IKTEST datapersistence \(value ? "PASS" : "FAIL") \(title)")
            if !value { failures += 1 }
        }
        let parts = arg.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2, let identifier = WebProfiles.persistenceTestIdentifier else {
            print("IKTEST datapersistencechecks FAIL needs write|read, a base URL and IKAGO_TEST_STORAGE_UUID")
            return
        }
        let phase = parts[0], probe = parts[1] + "/?data-persistence"
        let store = WebProfiles.dataStore(for: browser.state.activeSpace.profileID)
        check(store.isPersistent && store.identifier == identifier, "the Space uses the persistent fixture store")
        browser.open(probe, inNewTab: true)
        try? await Task.sleep(for: .milliseconds(1200))
        guard let page = browser.activeController?.page else { return check(false, "fixture page opened") }

        if phase == "write" {
            let expiry = Date().addingTimeInterval(30 * 86_400)
            if let cookie = HTTPCookie(properties: [.name: cookieName, .value: "native", .domain: cookieDomain,
                                                    .path: "/", .expires: expiry, .secure: true]) {
                await store.httpCookieStore.setCookie(cookie)
            }
            _ = try? await page.webView.callAsyncJavaScript(
                "document.cookie = 'ikagoPage=kept; max-age=2592000; path=/'; localStorage.setItem('ikagoPersist', 'kept'); return true",
                arguments: [:], in: nil, contentWorld: .page)
            // A second store object for the same identifier sees the same data, like a relaunch would.
            let reopened = await WKWebsiteDataStore(forIdentifier: identifier).httpCookieStore.allCookies()
            check(reopened.contains { $0.name == cookieName } && reopened.contains { $0.name == "ikagoPage" },
                  "a fresh store object for the identifier sees native and page cookies")
        } else {
            let cookies = await store.httpCookieStore.allCookies()
            check(cookies.contains { $0.name == cookieName && $0.value == "native" }, "a persistent cookie set through WKHTTPCookieStore survives relaunch")
            check(cookies.contains { $0.name == "ikagoPage" && $0.value == "kept" }, "a persistent cookie set by the page survives relaunch")
            let local = try? await page.webView.callAsyncJavaScript("return localStorage.getItem('ikagoPersist')",
                                                                    arguments: [:], in: nil, contentWorld: .page)
            check(local as? String == "kept", "localStorage survives relaunch")
            await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        }
        print("IKTEST datapersistencechecks \(phase) \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }
}
#endif
