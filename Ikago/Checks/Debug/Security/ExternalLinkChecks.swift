#if DEBUG
import AppKit

@MainActor
enum ExternalLinkChecks {
    static func run(_ browser: BrowserWindowController, base: String) async {
        var failures = 0
        func check(_ value: Bool, _ label: String) {
            print("IKTEST applinks \(value ? "PASS" : "FAIL") \(label)")
            if !value { failures += 1 }
        }
        let app = URL(fileURLWithPath: "/Applications/Fixture.app")
        let callback = URL(string: "fixture-app://oauth/callback?code=fixture%2Bcode&state=fixture%3Dstate#done")!
        var opened: [URL] = []
        var prompts = 0
        var approved = true
        let opener = ExternalLinkOpener(application: { _ in app }, confirm: { _, _, _ in
            prompts += 1
            return approved
        }, launch: { url, target in
            check(target == app, "opens the exact application approved by the user")
            opened.append(url)
        })
        await opener.open(callback, sourceHost: "fixture.invalid", in: browser.window)
        check(opened == [callback] && prompts == 1, "callback query and fragment survive the handoff")
        approved = false
        await opener.open(callback, sourceHost: "fixture.invalid", in: browser.window)
        check(opened.count == 1 && prompts == 2, "Cancel does not launch an application")
        for raw in ["javascript:alert(1)", "data:text/html,hello", "about:blank", "file:///tmp/a.html",
                    "ikago://settings", "webkit-extension://fixture/page", "https://example.com"] {
            check(!ExternalLinkOpener.isExternal(URL(string: raw)!), "browser scheme is never handed to macOS")
        }
        check(ExternalLinkOpener.isExternal(URL(string: "msauth.com.example://callback")!), "any registered app scheme is external")
        approved = true
        guard !base.isEmpty else { return }
        let tab = browser.state.newTab(url: base + "/start")!
        defer { browser.state.closeTab(tab.id) }
        try? await Task.sleep(for: .seconds(1))
        guard let controller = browser.content.controller(for: tab.id), let page = controller.page else {
            check(false, "live fixture page exists"); return
        }
        page.externalLinks = opener

        let beforeRedirect = opened.count
        page.load(base + "/redirect")
        try? await Task.sleep(for: .seconds(1))
        check(opened.count == beforeRedirect + 1 && opened.last == callback, "HTTP OAuth redirect opens the app")
        check(tab.loadError == nil && !ExternalLinkOpener.isExternal(URL(string: tab.url)!), "app callback does not replace the browser page or show a load error")

        page.load(base + "/start")
        try? await Task.sleep(for: .milliseconds(500))
        let beforeScript = opened.count
        _ = try? await page.callAsync("location.href = 'fixtureapp://open/item'; return true")
        try? await Task.sleep(for: .milliseconds(500))
        check(opened.count == beforeScript + 1 && opened.last?.scheme == "fixtureapp", "scripted Open in app navigation is handled")

        page.load(base + "/start")
        try? await Task.sleep(for: .milliseconds(500))
        let beforePopup = opened.count, tabs = browser.state.tabs.count
        _ = try? await page.callAsync("document.querySelector('#popup').click(); return true")
        try? await Task.sleep(for: .milliseconds(500))
        check(opened.count == beforePopup + 1 && browser.state.tabs.count == tabs, "new-window app link opens the app without a blank tab")

        page.load(base + "/iframe")
        try? await Task.sleep(for: .milliseconds(500))
        let beforeFrame = opened.count, beforePrompts = prompts
        _ = try? await page.callAsync("document.querySelector('iframe').src = 'fixtureapp://hidden'; return true")
        try? await Task.sleep(for: .milliseconds(500))
        check(opened.count == beforeFrame && prompts == beforePrompts, "hidden-frame scripted launches remain blocked")
        print("IKTEST applinkchecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }
}
#endif
