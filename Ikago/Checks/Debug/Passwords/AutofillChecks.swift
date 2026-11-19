#if DEBUG
import AppKit
import WebKit

/// Addresses and cards: the store (cards sealed to the vault's key, only valid numbers, nothing lost when passwords are
/// deleted), field recognition on a real page, filling an address and a card (never the security code), and the offer
/// to save after a form is submitted.
@MainActor
enum AutofillChecks {
    static func run(_ browser: BrowserWindowController, base: String) async {
        guard WebProfiles.isTestMode, URL(string: base)?.host == "127.0.0.1" else { return }
        var failures = 0
        func check(_ value: Bool, _ title: String) {
            print("IKTEST autofill \(value ? "PASS" : "FAIL") \(title)")
            if !value { failures += 1 }
        }
        let store = AutofillStore.shared, vault = PasswordVault.shared
        defer {
            AutofillSavePresenter.shared.dismissAll()
            try? store.deleteAllForChecks()
            try? vault.deleteAll()
        }
        try? store.deleteAllForChecks()
        try? vault.deleteAll()

        // Card numbers and the store.
        check(AutofillStore.isCardNumber("4242424242424242") && !AutofillStore.isCardNumber("4242424242424241"), "card numbers pass the Luhn check")
        check(AutofillStore.brand(of: "4242424242424242") == "Visa" && AutofillStore.brand(of: "5555555555554444") == "Mastercard"
              && AutofillStore.brand(of: "378282246310005") == "American Express", "brands are recognized")
        check((try? store.saveCard(number: "1234 5678", name: "A", expMonth: 1, expYear: 30)) == nil, "an invalid number isn't saved")
        try? store.saveCard(number: "4242 4242 4242 4242", name: "Ada Lovelace", expMonth: 4, expYear: 29)
        let card = store.cards.first
        check(card?.last4 == "4242" && card?.expYear == 2029 && card?.brand == "Visa", "a card keeps its last four digits, brand and expiry")
        check(card.map { !String(decoding: $0.number, as: UTF8.self).contains("4242424242424242") } == true, "its number is stored sealed")
        var opened: String?
        if let card { opened = try? await store.number(of: card, reason: "check") }
        check(opened == "4242424242424242", "the number opens with the vault's key")
        try? vault.deleteAll()
        var afterDelete: String?
        if let card { afterDelete = try? await store.number(of: card, reason: "check") }
        check(afterDelete == "4242424242424242", "deleting every password keeps the key saved cards need")
        check(store.knowsCard(last4: "4242", expMonth: 4, expYear: 29), "a saved card is recognized again")

        let parsed = AutofillFlow.parseCard(["cardNumber": "4242-4242-4242-4242", "cardExpiry": "04 / 29"])
        check(parsed?.number == "4242424242424242" && parsed?.month == 4 && parsed?.year == 2029, "an expiry like 04 / 29 is read")
        check(AutofillFlow.parseAddress(["givenName": "Ada", "familyName": "Lovelace", "line1": "1 Main St", "postalCode": "12345"])?.name
              == "Ada Lovelace", "a submitted address joins first and last names")
        check(AutofillFlow.parseAddress(["email": "a@b.test"]) == nil, "an email alone isn't an address")
        check(!AutofillFlow.isSecure(URL(string: "http://shop.test")) && AutofillFlow.isSecure(URL(string: "https://shop.test")),
              "only secure pages are filled")

        var home = AutofillAddress()
        home.name = "Ada Lovelace"; home.street = "1 Main St"; home.city = "London"; home.postalCode = "N1 1AA"
        home.country = "United Kingdom"; home.email = "ada@example.test"; home.phone = "+44 20 0000 0000"
        try? store.save(home)
        check(store.knows(home) && store.addresses.count == 1, "an address is saved and recognized")

        // A checkout page on WebKit.
        browser.open(base + "/?autofill", inNewTab: true)
        for _ in 0..<250 {
            if browser.state.activeTab?.isLoading == false && browser.state.activeTab?.url.hasSuffix("autofill") == true && browser.activeController?.page != nil { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        guard let page = browser.activeController?.page, let url = page.webView.url else { return check(false, "fixture loaded") }
        try? await Task.sleep(for: .milliseconds(300))
        _ = try? await page.webView.callAsyncJavaScript("""
            document.body.insertAdjacentHTML('beforeend', `<form id="ship">
              <input id="fname" name="first_name" placeholder="First name"><input id="lname" name="last_name" placeholder="Last name">
              <input id="addr" autocomplete="address-line1"><input id="zip" name="zip"><input id="city" name="city">
              <select id="country" name="country"><option value="">Choose</option><option value="US">United States</option><option value="GB">United Kingdom</option></select>
              <input id="mail" type="email"><button>Continue</button></form>
              <form id="pay"><input id="ccnum" autocomplete="cc-number"><input id="ccname" name="cardholder-name">
              <input id="ccexp" name="exp-date" placeholder="MM / YY" maxlength="7"><input id="cvc" name="cvc"></form>`)
            return true
            """, in: nil, contentWorld: .page)
        func kind(_ id: String) async -> String? {
            try? await page.webView.callAsyncJavaScript("return window.__ikagoFormFill.classify(document.getElementById(id))",
                                                       arguments: ["id": id], in: nil, contentWorld: .defaultClient) as? String
        }
        var kinds: [String: String] = [:]
        for id in ["fname", "lname", "addr", "zip", "city", "country", "mail", "ccnum", "ccname", "ccexp", "cvc"] { kinds[id] = await kind(id) }
        check(kinds == ["fname": "givenName", "lname": "familyName", "addr": "line1", "zip": "postalCode", "city": "city", "country": "country",
                        "mail": "email", "ccnum": "cardNumber", "ccname": "cardName", "ccexp": "cardExpiry", "cvc": "cardCode"],
              "fields are recognized from autocomplete, names and placeholders: \(kinds)")
        let origin = PasswordChooser.origin(of: url)
        func fill(_ focus: String, _ values: [String: Any], card: Bool) async -> Int? {
            try? await page.webView.callAsyncJavaScript("""
                document.getElementById(focus).focus()
                return window.__ikagoFormFill.fill(values, card, origin)
                """, arguments: ["focus": focus, "values": values, "card": card, "origin": origin], in: nil, contentWorld: .defaultClient) as? Int
        }
        func value(_ id: String) async -> String? {
            try? await page.webView.callAsyncJavaScript("return document.getElementById(id).value", arguments: ["id": id],
                                                       in: nil, contentWorld: .page) as? String
        }
        let filledAddress = await fill("fname", home.values, card: false)
        let address = [await value("fname"), await value("lname"), await value("addr"), await value("zip"), await value("country"), await value("mail")]
        check(filledAddress == 7 && address == ["Ada", "Lovelace", "1 Main St", "N1 1AA", "GB", "ada@example.test"],
              "an address fills the whole form, its country in the select: \(address)")
        let filledCard = await fill("ccnum", ["cardNumber": "4242424242424242", "cardName": "Ada Lovelace", "expMonth": 4, "expYear": 2029], card: true)
        let number = await value("ccnum"), expiry = await value("ccexp"), code = await value("cvc")
        check(filledCard == 3 && number == "4242424242424242" && expiry == "04/29", "a card fills its number, name and expiry")
        check(code == "", "the security code is never filled")
        let elsewhere = try? await page.webView.callAsyncJavaScript("return window.__ikagoFormFill.fill({ email: 'x' }, false, 'https://elsewhere.test')",
                                                                   in: nil, contentWorld: .defaultClient) as? Int
        check(elsewhere == 0, "values chosen for another origin fill nothing")

        // Fields the person can't see get nothing: a page showing only a name can't collect the street and phone.
        _ = try? await page.webView.callAsyncJavaScript("""
            document.body.insertAdjacentHTML('beforeend', `<form id="sneaky" style="margin-top:20px">
              <input id="s-name" name="name" placeholder="Name"><input id="s-mail" type="email" placeholder="Email">
              <input id="s-street" autocomplete="address-line1" style="position:absolute;left:-9999px">
              <input id="s-phone" type="tel" style="opacity:0">
              <div style="width:0;height:0;overflow:hidden"><input id="s-zip" name="zip"></div>
              <input id="s-city" name="city" style="clip-path:inset(50%)"><input id="s-tiny" name="country" style="width:1px;height:1px;padding:0;border:0"></form>`)
            document.getElementById('s-name').scrollIntoView()
            return true
            """, in: nil, contentWorld: .page)
        let sneaky = await fill("s-name", home.values, card: false)
        var leaked: [String] = []
        for id in ["s-street", "s-phone", "s-zip", "s-city", "s-tiny"] {
            if let filled = await value(id), !filled.isEmpty { leaked.append(id) }
        }
        let mail = await value("s-mail")
        check(sneaky == 2 && leaked.isEmpty && mail == "ada@example.test",
              "only visible fields are filled (\(sneaky ?? -1) filled; hidden ones filled: \(leaked))")

        // Submitting a new card offers to save it.
        _ = try? await page.webView.callAsyncJavaScript("""
            const form = document.getElementById('pay')
            form.addEventListener('submit', e => e.preventDefault())
            document.getElementById('ccnum').value = '5555 5555 5555 4444'
            document.getElementById('ccexp').value = '11/30'
            form.requestSubmit()
            return true
            """, in: nil, contentWorld: .page)
        for _ in 0..<30 where browser.chrome.autofillSave == nil { try? await Task.sleep(for: .milliseconds(100)) }
        check(browser.chrome.autofillSave?.card == true && browser.chrome.autofillSave?.title.contains("4444") == true,
              "a submitted new card is offered for saving")
        check(AutofillSavePresenter.shared.save() == nil && store.knowsCard(last4: "4444", expMonth: 11, expYear: 30), "saving it keeps it")
        print("IKTEST autofillchecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }
}
#endif
