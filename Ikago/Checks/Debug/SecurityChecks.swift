#if DEBUG
import Foundation
import WebKit

@MainActor
enum SecurityChecks {
    static func run(_ browser: BrowserWindowController, base: String) async {
        guard WebProfiles.isTestMode, URL(string: base)?.host == "127.0.0.1" else { return }
        var failures = 0
        func check(_ value: Bool, _ message: String) {
            print("IKTEST security \(value ? "PASS" : "FAIL") \(message)")
            if !value { failures += 1 }
        }
        let state = browser.state, prefs = state.browserPreferences, active = state.activeTabID
        let ids = Set(state.tabs.map(\.id))
        defer {
            state.browserPreferences = prefs; BrowserSecurity.shared.apply(prefs)
            for tab in state.tabs where !ids.contains(tab.id) { state.closeTab(tab.id, removingPin: true) }
            if let active { state.select(active) }
        }
        check(BrowserSecurity.shared.blockingIssue == nil, "native tracker and cookie rules compile: \(BrowserSecurity.shared.blockingIssue ?? "ready")")
        check(BrowserPreferences().blockTrackers ?? true, "common tracker blocking defaults on")
        check(BrowserPreferences().blockThirdPartyCookies ?? true, "third-party cookie blocking defaults on")
        state.browserPreferences.forceHTTPS = true; BrowserSecurity.shared.apply(state.browserPreferences)
        check(BrowserSecurity.shared.httpsPolicy == .errorOnFailure, "strict mode never requests silent fallback")
        check(BrowserSecurity.secureURL(URL(string: "http://example.com:80/a?q=1#test")!)?.absoluteString == "https://example.com/a?q=1#test", "upgrade preserves path/query and normalizes default port")
        state.browserPreferences.forceHTTPS = false; state.browserPreferences.warnInsecureHTTP = true
        BrowserSecurity.shared.apply(state.browserPreferences)
        check(BrowserSecurity.shared.httpsPolicy == .userMediatedFallbackToHTTP, "insecure fallback uses WebKit warning policy")
        state.browserPreferences.warnInsecureHTTP = false; BrowserSecurity.shared.apply(state.browserPreferences)
        check(BrowserSecurity.shared.httpsPolicy == .automaticFallbackToHTTP, "disabling warning restores automatic fallback")
        browser.open(base + "/", inNewTab: true)
        try? await Task.sleep(for: .milliseconds(700))
        if let page = browser.activeController?.page {
            do {
                let rule = try await WKContentRuleListStore(url: SessionStore.testDirectory.appending(path: "ContentRules")).compileContentRuleList(forIdentifier: "IkagoLocalSecurityFixture", encodedContentRuleList: BrowserSecurity.trackerJSON(domains: ["localhost"]))!
                let controller = page.webView.configuration.userContentController
                controller.add(rule)
                let remote = base.replacingOccurrences(of: "127.0.0.1", with: "localhost")
                let probe = "return await new Promise(resolve=>{const i=new Image(); i.onload=()=>resolve('loaded'); i.onerror=()=>resolve('blocked'); i.src='\(remote)/security-tracker.svg?'+Math.random(); setTimeout(()=>resolve('timeout'),3000)})"
                let blocked = try await page.callAsync(probe) as? String
                check(blocked == "blocked", "WebKit blocks third-party fixture resource before loading")
                controller.remove(rule)
                let loaded = try await page.callAsync(probe) as? String
                check(loaded == "loaded", "same resource loads after native list removal")
            } catch { check(false, error.localizedDescription) }
        } else { check(false, "fixture page exists") }
        let beforeCount = try? await URLSession.shared.data(from: URL(string: base + "/security-count")!).0
        state.browserPreferences.forceHTTPS = true; state.browserPreferences.httpsAllowLocal = false
        BrowserSecurity.shared.apply(state.browserPreferences)
        browser.open(base + "/security-http-probe", inNewTab: true)
        try? await Task.sleep(for: .milliseconds(1000))
        check(state.activeTab?.loadError != nil && state.activeTab?.url.hasPrefix("http:") != true, "strict HTTPS blocks insecure-only server without HTTP fallback")
        let afterCount = try? await URLSession.shared.data(from: URL(string: base + "/security-count")!).0
        check(beforeCount != nil && beforeCount == afterCount, "strict mode sends no plaintext HTTP probe request")
        state.browserPreferences.httpsAllowLocal = nil; BrowserSecurity.shared.apply(state.browserPreferences)
        browser.open(base + "/?local-allowed", inNewTab: true)
        try? await Task.sleep(for: .milliseconds(1000))
        check(state.activeTab?.loadError == nil && state.activeTab?.url.hasPrefix("http://127.0.0.1") == true, "HTTPS-only still opens a local HTTP dev server")
        state.browserPreferences.blockTrackers = false
        state.browserPreferences.blockThirdPartyCookies = false
        state.saveNow()
        let root = FileManager.default.temporaryDirectory.appending(path: "IkagoSecurityRestore-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            let store = SessionStore(directory: root)
            try store.save(state.snapshot())
            let restored = BrowserState(store: store)
            check(restored.browserPreferences.forceHTTPS == true && restored.browserPreferences.blockTrackers == false && restored.browserPreferences.blockThirdPartyCookies == false, "security controls survive restore")
        } catch { check(false, error.localizedDescription) }
        var exceptions = BrowserPreferences(); exceptions.forceHTTPS = true
        check(exceptions.allowsHTTP(host: "localhost") && exceptions.allowsHTTP(host: "127.0.0.1"), "HTTPS-only allows localhost by default")
        exceptions.httpsAllowLocal = false
        check(!exceptions.allowsHTTP(host: "127.0.0.1"), "localhost exception can be turned off")
        exceptions.httpsExceptions = "router.lan, http://dev.example.test:8080/"
        check(exceptions.allowsHTTP(host: "router.lan") && exceptions.allowsHTTP(host: "a.dev.example.test")
              && !exceptions.allowsHTTP(host: "evilrouter.lan") && !exceptions.allowsHTTP(host: "example.test"), "HTTP exceptions match hosts and subdomains only")
        check(BrowserPreferences().fraudulentWebsiteWarning ?? true, "fraudulent-website warnings default on")
        if let page = browser.activeController?.page {
            check(page.webView.configuration.preferences.isFraudulentWebsiteWarningEnabled, "pages start with fraud warnings on")
            state.browserPreferences.fraudulentWebsiteWarning = false; BrowserSecurity.shared.apply(state.browserPreferences)
            check(!page.webView.configuration.preferences.isFraudulentWebsiteWarningEnabled, "turning fraud warnings off reaches open pages")
            state.browserPreferences.fraudulentWebsiteWarning = nil; BrowserSecurity.shared.apply(state.browserPreferences)
            page.setDeveloperTools(false)
            check(!page.webView.isInspectable, "pages are not inspectable while developer tools are off")
            page.setDeveloperTools(state.developerTools)
        }
        state.browserPreferences.forceHTTPS = false; BrowserSecurity.shared.apply(state.browserPreferences)
        browser.open(base + "/", inNewTab: true)
        try? await Task.sleep(for: .milliseconds(700))
        if let page = browser.activeController?.page {
            _ = try? await page.callAsync("location.href = 'data:text/html,<h1>phish</h1>'; return 1")
            try? await Task.sleep(for: .milliseconds(600))
            check(page.webView.url?.scheme != "data", "a page can't open a top-level data: document")
        }
        await CookieIsolationChecks.run(browser, base: base, check: check)
        let lax = ImportedCookie(domain: "example.com", name: "a", value: "b", sameSite: 1).cookie
        check(lax?.sameSitePolicy == .sameSiteLax, "imported cookies keep SameSite=Lax")
        print("IKTEST securitychecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }
}
#endif
