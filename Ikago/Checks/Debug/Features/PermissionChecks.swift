#if DEBUG
import AppKit
import WebKit

/// Site permissions: how long each answer lasts (`PermissionGrant`), Allow Once ending when the tab leaves the site,
/// and one prompt in the window for a site asking more than once (`BrowserWindowController.finishPermission`).
@MainActor
enum PermissionChecks {
    static func run(_ browser: BrowserWindowController) async {
        let state = browser.state, original = state.browserPreferences.sitePermissions
        var failures = 0
        func check(_ value: Bool, _ title: String) {
            print("IKTEST permission \(value ? "PASS" : "FAIL") \(title)")
            if !value { failures += 1 }
        }
        defer {
            state.browserPreferences.sitePermissions = original
            print("IKTEST permissionchecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
        }
        let origin = "https://meet.example", host = "meet.example"

        // For a day: allowed until it runs out, then asks again.
        state.applyPermission(.allow(.day), kinds: .microphone, origin: origin, tabID: "t1")
        check(state.rememberedDecision(origin: origin, kinds: .microphone) == .allow, "Allow for a Day is granted without asking")
        check(state.sitePermissionExpiry(.microphone, host: host).map { $0 > Date().addingTimeInterval(23 * 3600) } == true,
              "it lasts a day")
        state.setSitePermission(.allow, .microphone, host: host, until: Date().addingTimeInterval(-1))
        check(state.rememberedDecision(origin: origin, kinds: .microphone) == nil, "once the day is over it asks again")
        state.applyPermission(.allow(.always), kinds: .microphone, origin: origin, tabID: "t1")
        check(state.sitePermissionExpiry(.microphone, host: host) == nil
              && state.rememberedDecision(origin: origin, kinds: .microphone) == .allow, "Always Allow has no end")
        state.applyPermission(.block, kinds: [.camera, .notifications], origin: origin, tabID: "t1")
        check(state.sitePermission(.camera, host: host) == .block && state.sitePermission(.notifications, host: host) == .block,
              "Don't Allow blocks every kind it was asked for, notifications too")
        state.setSitePermission(.ask, .microphone, host: host)
        state.setSitePermission(.ask, .camera, host: host)
        state.setSitePermission(.ask, .notifications, host: host)
        state.applyPermission(.dismiss, kinds: .camera, origin: origin, tabID: "t1")
        check(state.browserPreferences.sitePermissions?[host] == nil, "closing the prompt saves nothing")

        // Every kind, from either engine: Chromium's bits map onto the catalog, and one Ikago doesn't know is denied.
        check(PermissionRequest.Kinds.chromium(1 << 8) == .location && PermissionRequest.Kinds.chromium(1 << 4 | 1 << 13) == [.clipboard, .midi],
              "Chromium's location, clipboard and MIDI requests map onto Ikago's kinds")
        check(PermissionRequest.Kinds.chromium(1 << 30) == nil && PermissionRequest.Kinds.chromium(1 << 8 | 1 << 30) == nil,
              "a permission Ikago doesn't know is denied, even alongside a known one")
        check(Set(PermissionRequest.Kinds.catalog.map(\.key)).count == PermissionRequest.Kinds.catalog.count, "every kind saves under its own key")
        state.applyPermission(.allow(.day), kinds: [.location, .clipboard], origin: origin, tabID: "t1")
        check(state.rememberedDecision(origin: origin, kinds: .location) == .allow
              && state.sitePermissionExpiry(.clipboard, host: host) != nil, "location and clipboard save like the rest, for a day too")
        state.setSitePermission(.ask, .location, host: host)
        state.setSitePermission(.ask, .clipboard, host: host)

        // The site card lists what the site asked for, not the whole catalog.
        check(state.listedPermissions(host: host, tabID: nil).isEmpty, "a site that asked for nothing lists nothing")
        state.noteRequested(.location, origin: origin)
        check(state.listedPermissions(host: host, tabID: nil) == [.location], "a site's card lists what it asked for")
        state.setSitePermission(.block, .midi, host: host)
        check(state.listedPermissions(host: host, tabID: nil) == [.location, .midi], "and anything set for it")
        state.resetSitePermissions(host: host)
        check(state.browserPreferences.sitePermissions?[host] == nil, "Reset forgets the site's permissions")

        // Allow Once: for that tab while it stays on the site.
        state.applyPermission(.allow(.visit), kinds: .camera, origin: origin, tabID: "t1")
        check(state.rememberedDecision(origin: origin, kinds: .camera, tabID: "t1") == .allow, "Allow Once covers the tab's later requests")
        check(state.rememberedDecision(origin: origin, kinds: .camera, tabID: "t2") == nil, "but not another tab")
        check(state.browserPreferences.sitePermissions?[host] == nil, "and saves nothing")
        state.endVisitGrant(tabID: "t1", unless: host)
        check(state.visitGrants["t1"] != nil, "a page on the same site keeps it")
        state.endVisitGrant(tabID: "t1", unless: "elsewhere.example")
        check(state.rememberedDecision(origin: origin, kinds: .camera, tabID: "t1") == nil, "leaving the site ends it")

        // A site asking twice while its prompt is up gets one prompt, which answers both requests.
        guard let tab = state.newTab(url: "about:blank") else { return check(false, "opens a tab") }
        try? await Task.sleep(for: .milliseconds(500))
        guard let controller = browser.content.controller(for: tab.id) else {
            return check(false, "opens a tab")
        }
        var answers: [WKPermissionDecision] = []
        let first = PermissionRequest(origin: origin, kinds: .camera) { answers.append($0) }
        let second = PermissionRequest(origin: origin, kinds: .microphone) { answers.append($0) }
        browser.tabController(controller, requestsPermission: first)
        browser.tabController(controller, requestsPermission: second)
        check(browser.chrome.permissionPrompt?.kinds == [.camera, .microphone], "a second request joins the prompt on screen")
        browser.finishPermission(.allow(.visit))
        check(answers == [.grant, .grant] && browser.chrome.permissionPrompt == nil, "one answer resolves both, and no second prompt follows")
        let again = PermissionRequest(origin: origin, kinds: .microphone) { answers.append($0) }
        browser.tabController(controller, requestsPermission: again)
        check(answers.count == 3 && answers.last == .grant && browser.chrome.permissionPrompt == nil,
              "asking again on the same visit is answered without a prompt")
        state.closeTab(tab.id)
        check(state.visitGrants[tab.id] == nil, "closing the tab ends its Allow Once")
    }
}
#endif
