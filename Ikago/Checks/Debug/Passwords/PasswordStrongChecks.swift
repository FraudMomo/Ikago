#if DEBUG
import AppKit
import WebKit

/// Strong passwords: the generator's format and the site's rules, new-password fields recognized on a sign-up form,
/// the password filled into the field and its confirmation, and saved only when the person confirms after the form goes
/// through (a change-password form never replaces the saved login before that).
@MainActor
enum PasswordStrongChecks {
    static func run(_ browser: BrowserWindowController, base: String) async {
        guard WebProfiles.isTestMode, URL(string: base)?.host == "127.0.0.1" else { return }
        var failures = 0
        func check(_ value: Bool, _ title: String) {
            print("IKTEST passwordstrong \(value ? "PASS" : "FAIL") \(title)")
            if !value { failures += 1 }
        }

        // The generator.
        let samples = (0..<200).compactMap { _ in PasswordGenerator.generate() }
        let readable = try? NSRegularExpression(pattern: "^[a-zA-Z2-9]{6}-[a-zA-Z2-9]{6}-[a-zA-Z2-9]{6}$")
        check(samples.count == 200 && samples.allSatisfy { password in
            readable?.firstMatch(in: password, range: NSRange(password.startIndex..., in: password)) != nil
                && password.filter(\.isUppercase).count == 1 && password.contains(where: \.isNumber)
        }, "with no rules: three groups of six, one uppercase letter and a digit")
        check(Set(samples).count == samples.count, "every password is different")
        check(!samples.joined().contains(where: { "lIO01".contains($0) }), "no letters or digits that look alike")
        let siteRules = PasswordGenerator.Rules(passwordRules: "required: upper; required: digit; required: [!@#]; minlength: 12; maxlength: 16")
        let ruled = (0..<50).compactMap { _ in PasswordGenerator.generate(siteRules) }
        check(ruled.count == 50 && ruled.allSatisfy { PasswordGenerator.satisfies($0, siteRules) && (12...16).contains($0.count)
                                                       && $0.contains(where: { "!@#".contains($0) }) },
              "a site's passwordrules are kept: required classes, its symbols, its lengths")
        check(PasswordGenerator.generate(PasswordGenerator.Rules(maxLength: 10))?.count == 10, "a field's maxlength is kept")
        check(PasswordGenerator.generate(PasswordGenerator.Rules(passwordRules: "minlength: 30; maxlength: 10")) == nil,
              "rules that contradict each other give no password rather than a wrong one")
        let counts = (0..<4000).reduce(into: [Int](repeating: 0, count: 8)) { counts, _ in counts[PasswordGenerator.random(8)] += 1 }
        check(counts.allSatisfy { (400...600).contains($0) }, "random picks are even")

        // A sign-up form on WebKit.
        let state = browser.state, vault = PasswordVault.shared
        defer {
            try? vault.deleteAll()
            state.browserPreferences.passwordSource = nil
            BrowserSecurity.shared.apply(state.browserPreferences)
        }
        try? vault.deleteAll()
        state.browserPreferences.passwordSource = PasswordSource.ikago.rawValue
        BrowserSecurity.shared.apply(state.browserPreferences)
        browser.open(base + "/?passwords-strong", inNewTab: true)
        for _ in 0..<250 {
            if state.activeTab?.isLoading == false && state.activeTab?.url.hasSuffix("passwords-strong") == true && browser.activeController?.page != nil { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        guard let page = browser.activeController?.page, let url = page.webView.url else { return check(false, "fixture loaded") }
        try? await Task.sleep(for: .milliseconds(300))
        _ = try? await page.webView.callAsyncJavaScript("""
            document.body.insertAdjacentHTML('beforeend', '<form id="signup"><input id="email" type="email" name="email" value="new@example.test">' +
              '<input id="pw" type="password" autocomplete="new-password"><input id="pw2" type="password"><button>Create account</button></form>')
            return true
            """, in: nil, contentWorld: .page)
        func key() async -> [String: Any]? {
            _ = try? await page.webView.callAsyncJavaScript("document.getElementById('pw').focus(); return true", in: nil, contentWorld: .defaultClient)
            try? await Task.sleep(for: .milliseconds(400))
            return try? await page.webView.callAsyncJavaScript("return window.__ikagoPasswordKey.state()", in: nil, contentWorld: .defaultClient)
                as? [String: Any]
        }
        let shown = await key()
        check(shown?["visible"] as? Bool == true && shown?["newPassword"] as? Bool == true, "a new-password field shows the key for a strong password")
        guard let password = PasswordGenerator.generate() else { return check(false, "a password is made") }
        let filled = try? await page.webView.callAsyncJavaScript("return window.__ikagoPasswordKey.fillNew(password, origin)",
            arguments: ["password": password, "origin": PasswordChooser.origin(of: url)], in: nil, contentWorld: .defaultClient) as? [String: Any]
        let values = try? await page.webView.callAsyncJavaScript(
            "return [document.getElementById('pw').value, document.getElementById('pw2').value]", in: nil, contentWorld: .page) as? [String]
        check(values == [password, password] && filled?["filled"] as? Int == 2, "the password fills the field and its confirmation")
        check(filled?["username"] as? String == "new@example.test", "the form's username comes along")
        let wrongOrigin = try? await page.webView.callAsyncJavaScript("return window.__ikagoPasswordKey.fillNew('x', 'https://elsewhere.test')",
            in: nil, contentWorld: .defaultClient) as? Bool
        check(wrongOrigin == false, "another origin's request fills nothing")
        // Nothing is saved until the person confirms the card after the form goes through.
        let host = url.host ?? ""
        PasswordChooser.rememberStrong(password, host: host)
        check(vault.logins.isEmpty, "filling a strong password saves nothing by itself")
        PasswordSaving.submitted(username: "new@example.test", password: password, host: host, pageURL: url, isPrivate: false, in: page.webView)
        let offer = browser.chrome.passwordSave
        check(offer?.strong == true && offer?.username == "new@example.test" && offer?.update == false,
              "the sign-up offers to save the strong password with its username")
        check(PasswordSavePresenter.shared.save() == nil && vault.logins.map(\.username) == ["new@example.test"],
              "saved once the person confirms")
        let unlocked = try? await vault.passwords(for: vault.logins.filter { $0.username == "new@example.test" }, reason: "check")
        check(unlocked?.first?.1 == password, "the saved password is the one filled")

        // A change-password form: the saved login stays as it is until the change goes through and the person updates it.
        guard let next = PasswordGenerator.generate() else { return check(false, "a second password is made") }
        PasswordChooser.rememberStrong(next, host: host)
        let kept = try? await vault.passwords(for: vault.logins, reason: "check")
        check(kept?.first?.1 == password, "a strong password filled into a change form doesn't replace the saved one")
        PasswordSaving.submitted(username: "new@example.test", password: next, host: host, pageURL: url, isPrivate: false, in: page.webView)
        check(browser.chrome.passwordSave?.update == true, "after the change goes through, the person is asked to update it")
        PasswordSavePresenter.shared.dismiss()

        // Strong passwords are offered only where they can be saved.
        check(PasswordChooser.offersStrongPasswords(for: URL(string: "https://example.test"), isPrivate: false), "offered on HTTPS")
        check(!PasswordChooser.offersStrongPasswords(for: URL(string: "http://example.test"), isPrivate: false), "never on plain HTTP")
        check(!PasswordChooser.offersStrongPasswords(for: URL(string: "https://example.test"), isPrivate: true), "never in a private window")
        state.browserPreferences.passwordSuggestStrong = false
        BrowserSecurity.shared.apply(state.browserPreferences)
        check(!PasswordChooser.offersStrongPasswords(for: URL(string: "https://example.test"), isPrivate: false), "and not when turned off")
        state.browserPreferences.passwordSuggestStrong = nil
        print("IKTEST passwordstrongchecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }
}
#endif
