#if DEBUG
import AppKit

/// Agent access end to end on WebKit: the server refuses requests without the token or from a page, the outline is
/// compact with stable refs, actions return only what changed, the person's active tab never moves, passwords are
/// refused, card numbers are hidden and refused, consequential actions wait for the person however they're sent (and Allow
/// on a site sticks), and Pause and Stop hold.
@MainActor
enum AgentChecks {
    static func run(_ browser: BrowserWindowController, base: String) async {
        guard WebProfiles.isTestMode, URL(string: base)?.host == "127.0.0.1" else { return }
        var failures = 0
        func check(_ value: Bool, _ title: String) {
            print("IKTEST agent \(value ? "PASS" : "FAIL") \(title)")
            if !value { failures += 1 }
        }
        let state = browser.state, activity = AgentActivity.shared
        defer {
            activity.stopAll()
            state.browserPreferences.agentAccess = nil
            BrowserSecurity.shared.apply(state.browserPreferences)
            AgentServer.shared.update()
            print("IKTEST agentchecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
        }
        state.browserPreferences.agentAccess = true
        BrowserSecurity.shared.apply(state.browserPreferences)
        AgentServer.shared.update()
        for _ in 0..<50 where AgentServer.shared.endpoint == nil { try? await Task.sleep(for: .milliseconds(50)) }

        // The server: only with the token, never from a page.
        func status(headers: [String: String], body: String) async -> (Int, [String: Any]?) {
            guard let endpoint = AgentServer.shared.endpoint, let url = URL(string: endpoint) else { return (0, nil) }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = Data(body.utf8)
            for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
            guard let (data, response) = try? await URLSession.shared.data(for: request) else { return (0, nil) }
            return ((response as? HTTPURLResponse)?.statusCode ?? 0, try? JSONSerialization.jsonObject(with: data) as? [String: Any])
        }
        let initialize = #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","clientInfo":{"name":"checks"}}}"#
        let bearer = "Bearer " + AgentCredentials.token
        check(await status(headers: [:], body: initialize).0 == 401, "no token: refused")
        check(await status(headers: ["Authorization": "Bearer wrong"], body: initialize).0 == 401, "a wrong token: refused")
        check(await status(headers: ["Authorization": bearer, "Origin": "https://evil.test"], body: initialize).0 == 403, "a web page: refused")
        let hello = await status(headers: ["Authorization": bearer], body: initialize)
        check(hello.0 == 200 && (hello.1?["result"] as? [String: Any])?["instructions"] != nil, "the token: the handshake answers with instructions")
        let listed = await status(headers: ["Authorization": bearer], body: #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#)
        let names = ((listed.1?["result"] as? [String: Any])?["tools"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
        check(names.contains("outline") && names.contains("click") && !names.contains("evaluate"), "tools are listed; scripts only when allowed")

        // Tools on a page, beside the person's own tab.
        let personal = state.activeTabID
        func call(_ name: String, _ arguments: [String: Any]) async -> (text: String, failed: Bool) {
            let outcome = await AgentTools.call(name, arguments)
            return (outcome.content.first?["text"] as? String ?? "", outcome.isError)
        }
        let opened = await call("tab_open", ["url": base + "/?agent-fixture"])
        let tab = opened.text.split(separator: "\n").first.map { String($0.dropFirst(4)) } ?? ""
        check(!opened.failed && tab.hasPrefix("t"), "tab_open names the tab shortly: \(tab)")
        check(state.activeTabID == personal, "the agent's tab opens in the background; the person's tab stays active")
        guard let page = try? await AgentBrowser.page(AgentBrowser.resolve(tab)) else { return check(false, "the agent's page exists") }
        _ = try? await page.callAsync("""
            document.body.innerHTML = '<main><h1>Shop</h1><form onsubmit="event.preventDefault(); document.getElementById(\\'m\\').textContent = \\'Thanks\\'">' +
              '<label>Email <input id="email"></label><label>Password <input id="pw" type="password"></label><button>Sign up</button></form>' +
              '<p id="m"></p><button id="buy" onclick="this.textContent=\\'Bought\\'">Buy now</button><ul>' +
              Array.from({ length: 40 }, (_, i) => '<li>Item ' + i + '</li>').join('') + '</ul></main>'
            return true
            """)
        let outline = await call("outline", ["tab": tab])
        check(outline.text.contains("textbox \"Email\"") && outline.text.contains("password \"Password\"") && outline.text.contains("more ["),
              "the outline lists controls by name and collapses long lists")
        check(outline.text.count < 1500, "the outline is compact (\(outline.text.count) characters)")
        func ref(_ name: String) -> String? {
            guard let line = outline.text.split(separator: "\n").first(where: { $0.contains("\"\(name)\"") }),
                  let open = line.firstIndex(of: "["), let close = line.firstIndex(of: "]"), open < close else { return nil }
            return String(line[line.index(after: open)..<close])
        }
        guard let email = ref("Email"), let password = ref("Password"), let signUp = ref("Sign up"), let buy = ref("Buy now") else {
            return check(false, "refs found in the outline")
        }
        let typed = await call("type", ["tab": tab, "ref": email, "text": "ada@example.test"])
        check(!typed.failed && typed.text.contains("ada@example.test") && typed.text.count < 300, "typing returns only the change: \(typed.text)")
        check(await call("type", ["tab": tab, "ref": password, "text": "secret"]).failed, "typing into a password field is refused")
        let submitted = await call("click", ["tab": tab, "ref": signUp])
        check(submitted.text.contains("Thanks"), "a click returns the text that appeared: \(submitted.text)")
        check(state.activeTabID == personal, "acting never takes the person's tab")
        let again = await call("outline", ["tab": tab])
        check(again.text.contains("[\(email)] textbox \"Email\""), "refs stay the same across outlines")
        let gone = await call("click", ["tab": tab, "ref": "e9999"])
        check(gone.failed && gone.text.contains("get a new outline"), "a stale ref is reported, never guessed")

        // A risky click waits for the person: denied, then allowed.
        let denied = Task { await call("click", ["tab": tab, "ref": buy]) }
        for _ in 0..<40 where activity.approvals.isEmpty { try? await Task.sleep(for: .milliseconds(50)) }
        check(activity.approvals.first?.action.contains("Buy now") == true, "Buy now asks the person first")
        if let approval = activity.approvals.first { activity.answer(approval.id, allow: false) }
        check(await denied.value.failed, "denied: nothing is clicked")
        let allowed = Task { await call("click", ["tab": tab, "ref": buy]) }
        for _ in 0..<40 where activity.approvals.isEmpty { try? await Task.sleep(for: .milliseconds(50)) }
        if let approval = activity.approvals.first { activity.answer(approval.id, allow: true) }
        check(await allowed.value.text.contains("Bought"), "allowed: it goes ahead")

        // A checkout: every way to send it asks first, card fields are the person's, and Allow on a site sticks.
        _ = try? await page.callAsync("""
            document.body.innerHTML = '<main><form id="pay" onsubmit="event.preventDefault(); document.getElementById(\\'done\\').textContent = \\'Ordered\\'">' +
              '<label>Card number <input id="cc" autocomplete="cc-number"></label><label>ZIP <input id="zip"></label>' +
              '<button>Place order</button></form><p id="done"></p><label>PIN <input id="pin" type="password"></label>' +
              '<button id="buy" onclick="this.textContent=\\'Bought\\'">Buy now</button></main>'
            return true
            """)
        _ = try? await page.callAsync("document.getElementById('cc').value = '4242424242424242'; return true")
        let checkout = await call("outline", ["tab": tab])
        func ref(in text: String, _ name: String) -> String? {
            guard let line = text.split(separator: "\n").first(where: { $0.contains("\"\(name)\"") }),
                  let open = line.firstIndex(of: "["), let close = line.firstIndex(of: "]"), open < close else { return nil }
            return String(line[line.index(after: open)..<close])
        }
        check(!checkout.text.contains("4242") && checkout.text.contains("hidden from agents"), "a card number is never shown to the agent")
        guard let card = ref(in: checkout.text, "Card number"), let zip = ref(in: checkout.text, "ZIP"),
              let order = ref(in: checkout.text, "Place order"), let pin = ref(in: checkout.text, "PIN"),
              let buyNow = ref(in: checkout.text, "Buy now") else { return check(false, "checkout refs found") }
        check(await call("type", ["tab": tab, "ref": card, "text": "4000000000000002"]).failed, "typing a card number is refused")
        _ = await call("click", ["tab": tab, "ref": pin])
        check(await call("press", ["tab": tab, "key": "a"]).failed, "keys into a focused password field are refused")
        func asks(_ name: String, _ arguments: [String: Any], _ title: String) async {
            let pending = Task { await call(name, arguments) }
            for _ in 0..<40 where activity.approvals.isEmpty { try? await Task.sleep(for: .milliseconds(50)) }
            check(!activity.approvals.isEmpty, title)
            if let approval = activity.approvals.first { activity.answer(approval.id, .deny) }
            check(await pending.value.failed, title + ": denied, nothing happens")
        }
        await asks("type", ["tab": tab, "ref": zip, "text": "10001", "submit": true], "type with submit in a payment form asks first")
        await asks("press", ["tab": tab, "ref": zip, "key": "Enter"], "Enter in a payment form's field asks first")
        _ = try? await page.callAsync("document.querySelector('#pay button').focus(); return true")
        await asks("press", ["tab": tab, "key": "Enter"], "Enter on a focused Place order button asks first")
        let placed = Task { await call("click", ["tab": tab, "ref": order]) }
        for _ in 0..<40 where activity.approvals.isEmpty { try? await Task.sleep(for: .milliseconds(50)) }
        check(activity.approvals.first?.site == "127.0.0.1", "the approval names the site")
        if let approval = activity.approvals.first { activity.answer(approval.id, .site) }
        check(await placed.value.text.contains("Ordered"), "Allow on this site: it goes ahead")
        check(await call("click", ["tab": tab, "ref": buyNow]).text.contains("Bought") && activity.approvals.isEmpty,
              "and the next consequential action on the site doesn't ask again")
        activity.forget(site: "127.0.0.1")
        state.browserPreferences.agentActsWithoutAsking = true
        BrowserSecurity.shared.apply(state.browserPreferences)
        _ = try? await page.callAsync("document.getElementById('done').textContent = ''; return true")
        _ = await call("outline", ["tab": tab])
        check(await call("click", ["tab": tab, "ref": order]).text.contains("Ordered") && activity.approvals.isEmpty,
              "with asking off, agents act without asking")
        check(await call("type", ["tab": tab, "ref": card, "text": "4000000000000002"]).failed, "but still never type card numbers")
        state.browserPreferences.agentActsWithoutAsking = nil
        BrowserSecurity.shared.apply(state.browserPreferences)

        // Pause holds actions; Stop ends the agent's hold on the tab.
        let id = AgentBrowser.resolve(tab)
        activity.setPaused(id, true)
        let held = Task { await call("scroll", ["tab": tab]) }
        try? await Task.sleep(for: .milliseconds(400))
        check(activity.tabs[id]?.working != true, "paused: the action waits")
        let reading = Task { await call("outline", ["tab": tab]) }
        try? await Task.sleep(for: .milliseconds(300))
        activity.setPaused(id, false)
        check(!(await held.value.failed), "resumed: it continues")
        check(!(await reading.value.failed), "reading waits while paused too, then continues")
        activity.stop(id)
        check(await call("click", ["tab": tab, "ref": email]).failed, "stopped: the agent can't act there again")
        state.closeTab(id)
    }
}
#endif
