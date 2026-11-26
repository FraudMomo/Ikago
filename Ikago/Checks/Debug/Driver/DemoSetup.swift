#if DEBUG
import AppKit

/// The hands-on demo (`scripts/demo.sh`): fills a disposable test profile with sample logins, an address and a card, turns
/// on agents for the demo agent, and opens the demo site. Test mode only, so nothing reaches the person's own profile.
@MainActor
enum DemoSetup {
    /// The sample logins. One username on three sites of one domain (one row, "3 sites", with different passwords), more
    /// usernames than fit at a glance (the search field), a saved title, and a login with no username on a second site.
    static let logins: [(site: String, title: String?, username: String, password: String)] = [
        ("accounts.ikago-demo.localhost", nil, "sam@example.com", "demo-accounts-password"),
        ("ikago-demo.localhost", nil, "sam@example.com", "demo-accounts-password"),
        ("mail.ikago-demo.localhost", nil, "sam@example.com", "demo-mail-password"),
        ("accounts.ikago-demo.localhost", nil, "sam.work@example.com", "demo-work-password"),
        ("accounts.ikago-demo.localhost", "Family account", "family@example.com", "demo-family-password"),
        ("mail.ikago-demo.localhost", nil, "oldname", "demo-old-password"),
        ("blog-demo.localhost", nil, "reader@example.com", "demo-blog-password"),
        ("blog-demo.localhost", nil, "", "demo-no-username-password"),
    ]

    /// `<port>[,chromium]`: the demo server's port on this Mac.
    static func run(_ browser: BrowserWindowController, arg: String) async {
        guard WebProfiles.isTestMode else { return }
        let parts = arg.split(separator: ",").map(String.init)
        guard let port = parts.first.flatMap(Int.init) else { return print("IKTEST demo needs the server's port") }
        let state = browser.state

        let vault = PasswordVault.shared, store = AutofillStore.shared
        try? vault.deleteAll()
        try? store.deleteAllForChecks()
        _ = try? vault.add(logins.map { .init(url: "http://\($0.site):\(port)/", title: $0.title, username: $0.username, password: $0.password) })
        var home = AutofillAddress()
        home.name = "Sam Example"; home.street = "1 Demo Street"; home.city = "Springfield"; home.region = "IL"
        home.postalCode = "62701"; home.country = "United States"; home.email = "sam@example.com"; home.phone = "+1 555 0100"
        try? store.save(home)
        try? store.saveCard(number: "4242 4242 4242 4242", name: "Sam Example", expMonth: 4, expYear: 2030)  // a test number

        // Bookmarks for Ikago Home: a few pages and a folder of them.
        if state.bookmarks.isEmpty {
            let base = "http://ikago-demo.localhost:\(port)"
            let pages = [("Ikago Demo", "/"), ("Sign in", "/signin.html"), ("Checkout", "/checkout.html"), ("Demo Shop", "/agent.html")]
            state.bookmarks = pages.map { Bookmark(url: base + $0.1, title: $0.0) }
            if let folder = state.createBookmarkFolder(named: "Password demos") {
                state.bookmarks += [("Sign up", "/signup.html"), ("Change password", "/change.html"), ("PIN only", "/pin.html")]
                    .map { Bookmark(url: base + $0.1, title: $0.0, folderID: folder.id) }
            }
        }

        // The demo agent drives the tab the person is looking at, on a port of its own (never the installed Ikago's).
        state.browserPreferences.agentAccess = true
        state.browserPreferences.agentUsesOpenTabs = true
        state.browserPreferences.agentPort = port + 1
        if parts.contains("chromium") { state.browserPreferences.preferredEngine = .chromium }
        BrowserSecurity.shared.apply(state.browserPreferences)
        AgentServer.shared.update()
        state.saveNow()
        for _ in 0..<100 where AgentServer.shared.endpoint == nil { try? await Task.sleep(for: .milliseconds(50)) }
        // The demo server reads this to play the agent; it lives only in the disposable profile.
        let token = SessionStore.testDirectory.appending(path: "demo-agent.json")
        let info = ["endpoint": AgentServer.shared.endpoint ?? "", "token": AgentCredentials.token]
        if let data = try? JSONSerialization.data(withJSONObject: info) { try? data.write(to: token, options: .atomic) }
        print("IKTEST demo ready agent=\(AgentServer.shared.endpoint ?? "none")")
        browser.open("http://ikago-demo.localhost:\(port)/", inNewTab: false)
    }

    // MARK: Showing one component at a time (screenshots of the overlays)

    /// strong | nousername | update | regular | off: a password save card for the current page.
    static func saveCard(_ kind: String, _ browser: BrowserWindowController) {
        let presenter = PasswordSavePresenter.shared
        let site = URL(string: browser.state.activeTab?.url ?? "")?.host.map(PasswordVault.site) ?? "example.com"
        switch kind {
        case "strong": presenter.offer(site: site, username: "new@example.com", password: "x", update: false, strong: true, in: browser)
        case "nousername": presenter.offer(site: site, username: "", password: "x", update: false, strong: true, in: browser)
        case "update": presenter.offer(site: site, username: "sam.work@example.com", password: "x", update: true, in: browser)
        case "regular": presenter.offer(site: site, username: "sam@example.com", password: "x", update: false, in: browser)
        default: presenter.dismiss()
        }
    }

    /// address | card | off: an autofill save card.
    static func autofillCard(_ kind: String, _ browser: BrowserWindowController) {
        switch kind {
        case "address":
            var address = AutofillAddress()
            address.name = "Alex Example"; address.street = "9 New Road"; address.city = "Portland"; address.postalCode = "97201"
            AutofillSavePresenter.shared.offer([.address(address)], in: browser)
        case "card": AutofillSavePresenter.shared.offer([.card(number: "5555555555554444", name: "Alex Example", month: 8, year: 2031)], in: browser)
        default: AutofillSavePresenter.shared.dismissAll()
        }
    }

    /// working[,client] | paused | approval | allowsite | stop: the agent bar and chip on the current tab. The client is
    /// the MCP name an agent would send ("claude-code" unless given, "codex-mcp-client", "gemini-cli"…).
    static func agent(_ kind: String, _ browser: BrowserWindowController) {
        let activity = AgentActivity.shared
        guard let tab = browser.state.activeTabID else { return }
        let host = URL(string: browser.state.activeTab?.url ?? "")?.host ?? "example.com"
        let parts = kind.split(separator: ",").map(String.init)
        switch parts.first ?? "" {
        case "working":
            let identity = AgentIdentity(client: parts.count > 1 ? parts[1] : "claude-code")
            activity.connected(identity)
            AgentActivity.$current.withValue(identity) { activity.adopt(tab) }
            activity.setPaused(tab, false)
            activity.begin(tab, "Typing “running shoes” in Search")
        case "paused": activity.setPaused(tab, true)
        case "approval":
            activity.setPaused(tab, false)
            Task { _ = await activity.approve(tab, action: "Click “Buy now”", host: host) }
        case "activityopen": AgentActivityCard.startsOpen = true
        case "allowsite": if let approval = activity.approval(for: tab) { activity.answer(approval.id, .site) }
        default: activity.stopAll()
        }
    }
}
#endif
