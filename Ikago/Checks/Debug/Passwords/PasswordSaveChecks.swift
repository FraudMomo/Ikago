#if DEBUG
import AppKit
import WebKit

/// Saving logins on WebKit: a sign-in is offered only once the page confirms it, an identical one is recognized
/// without Touch ID, a changed one is offered as an update, and only new logins are exported.
@MainActor
enum PasswordSaveChecks {
    static func run(_ browser: BrowserWindowController, base: String) async {
        guard WebProfiles.isTestMode, URL(string: base)?.host == "127.0.0.1" else { return }
        var failures = 0
        func check(_ value: Bool, _ title: String) {
            print("IKTEST passwordsave \(value ? "PASS" : "FAIL") \(title)")
            if !value { failures += 1 }
        }
        let state = browser.state, vault = PasswordVault.shared
        defer {
            PasswordSavePresenter.shared.dismiss()
            try? vault.deleteAll()
            state.browserPreferences.passwordSource = nil
            BrowserSecurity.shared.apply(state.browserPreferences)
        }
        try? vault.deleteAll()
        state.browserPreferences.passwordSource = PasswordSource.ikago.rawValue
        BrowserSecurity.shared.apply(state.browserPreferences)
        browser.open(base + "/?passwords-save", inNewTab: true)
        for _ in 0..<250 {
            if state.activeTab?.isLoading == false && state.activeTab?.url.hasSuffix("passwords-save") == true && browser.activeController?.page != nil { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        guard let page = browser.activeController?.page else { return check(false, "fixture loaded") }
        try? await Task.sleep(for: .milliseconds(300))

        /// A sign-in form; `succeeds` removes it after submit like a page that signed in, otherwise it stays (rejected).
        func signIn(_ user: String, _ password: String, succeeds: Bool) async -> PasswordSaveOffer? {
            PasswordSavePresenter.shared.dismiss()
            _ = try? await page.webView.callAsyncJavaScript("""
                document.getElementById('signin')?.remove()
                document.body.insertAdjacentHTML('beforeend', '<form id="signin"><input id="su" name="username" autocomplete="username"><input id="sp" type="password"><button>Sign in</button></form>')
                const form = document.getElementById('signin')
                form.addEventListener('submit', e => { e.preventDefault(); if (succeeds) setTimeout(() => form.remove(), 150) })
                document.getElementById('su').value = user
                document.getElementById('sp').value = password
                form.requestSubmit()
                return true
                """, arguments: ["user": user, "password": password, "succeeds": succeeds], in: nil, contentWorld: .page)
            for _ in 0..<30 {
                try? await Task.sleep(for: .milliseconds(100))
                if let offer = browser.chrome.passwordSave { return offer }
            }
            return nil
        }

        check(await signIn("sam", "first secret", succeeds: false) == nil, "a rejected sign-in (form stays) isn't offered")
        let offer = await signIn("sam", "first secret", succeeds: true)
        check(offer?.update == false && offer?.username == "sam", "a sign-in that went through is offered for saving")
        check(PasswordSavePresenter.shared.save() == nil, "saving the offered login works")
        let saved = vault.logins.first { $0.username == "sam" }
        check(saved?.savedHere == true && saved?.fingerprint != nil && saved?.exported == nil, "the saved login is marked new for Apple Passwords")
        check(await signIn("sam", "first secret", succeeds: true) == nil, "signing in again with the same password offers nothing")
        let update = await signIn("sam", "second secret", succeeds: true)
        check(update?.update == true, "a changed password is offered as an update")
        PasswordSavePresenter.shared.dismiss()

        check(vault.unexported.count == 1, "one login waits for export")
        try? vault.markExported(Set(vault.unexported.map(\.id)))
        check(vault.unexported.isEmpty, "exported logins aren't exported again")
        _ = await signIn("sam", "second secret", succeeds: true)
        _ = PasswordSavePresenter.shared.save()
        check(vault.unexported.count == 1 && vault.logins.filter { $0.username == "sam" }.count == 1,
              "an updated password replaces the login and is new to Apple Passwords again")
        let plain = try? await vault.passwords(for: vault.unexported, reason: "check")
        check(plain?.first?.1 == "second secret", "the export decrypts the updated password")
        print("IKTEST passwordsavechecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }
}
#endif
