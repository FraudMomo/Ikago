import AppKit

/// Filling and saving addresses and cards, the same on both engines: what a focused field may be offered, the values
/// for the one the person picks (a card's number only after Touch ID), and turning a submitted form into an offer to save.
@MainActor
enum AutofillFlow {
    private static var preferences: BrowserPreferences { BrowserSecurity.shared.preferences }

    static var fillsAddresses: Bool { preferences.autofillAddresses ?? true }
    static var fillsCards: Bool { preferences.autofillCards ?? true }
    static var offersSave: Bool { preferences.autofillOfferSave ?? true }

    /// A secure page (HTTPS, or local development): cards and addresses never go to a plain-HTTP page.
    static func isSecure(_ url: URL?) -> Bool {
        BrowserPreferences.isSecurePage(url)
    }

    /// Whether the page's scripts should run at all: something to fill, or forms worth offering to save.
    static func watches(_ url: URL?, isPrivate: Bool) -> Bool {
        guard isSecure(url) else { return false }
        return fillsAddresses || fillsCards || (offersSave && !isPrivate)
    }

    /// The values for a field the person focused (`report` from the script), after they pick a saved address or card; nil
    /// when there's nothing to offer or they dismissed it. `view` shows the list; `field` is in its coordinates.
    static func choose(report: [String: Any], url: URL, in view: NSView, field: NSRect?) async -> (values: [String: Any], card: Bool)? {
        guard isSecure(url), let kind = report["kind"] as? String else { return nil }
        let card = kind == "card"
        let store = AutofillStore.shared
        let rows: [AutofillSuggestions.Row]
        if card {
            guard fillsCards else { return nil }
            rows = store.orderedCards.map { .init(id: $0.id, title: $0.title, detail: [$0.name, $0.expiry].filter { !$0.isEmpty }.joined(separator: " · ")) }
        } else {
            guard fillsAddresses else { return nil }
            rows = store.orderedAddresses.map { .init(id: $0.id, title: $0.title, detail: $0.summary.isEmpty ? $0.email : $0.summary) }
        }
        guard !rows.isEmpty, let window = view.window else { return nil }
        let chosen: UUID?
        #if DEBUG || IKAGO_CHECKS
        if SealedStorage.picksFirstChoice { chosen = rows.first?.id } else { chosen = await present(rows, card: card, view: view, field: field, window: window) }
        #else
        chosen = await present(rows, card: card, view: view, field: field, window: window)
        #endif
        guard let chosen else { return nil }
        if card {
            guard let saved = store.cards.first(where: { $0.id == chosen }),
                  let number = try? await store.number(of: saved, reason: "fill your card ending \(saved.last4)") else { return nil }
            store.markUsed(card: saved.id)
            return (["cardNumber": number, "cardName": saved.name, "expMonth": saved.expMonth, "expYear": saved.expYear], true)
        }
        guard let address = store.addresses.first(where: { $0.id == chosen }) else { return nil }
        store.markUsed(address: address.id)
        return (address.values, false)
    }

    private static func present(_ rows: [AutofillSuggestions.Row], card: Bool, view: NSView, field: NSRect?, window: NSWindow) async -> UUID? {
        let anchor: NSRect
        if let field { anchor = view.convert(field, to: nil) } else {
            let point = window.convertPoint(fromScreen: NSEvent.mouseLocation)
            anchor = NSRect(x: point.x - 1, y: point.y - 10, width: 2, height: 20)
        }
        return await AutofillSuggestionsPresenter.shared.present(rows, card: card, anchor: anchor, in: window)
    }

    /// A submitted form's address and card (field kind → text, from the script): offered for saving unless already saved.
    /// Private windows never offer.
    static func submitted(address: [String: String]?, card: [String: String]?, pageURL: URL?, isPrivate: Bool, in view: NSView) {
        guard offersSave, !isPrivate, isSecure(pageURL), let controller = view.window?.windowController as? BrowserWindowController,
              !controller.state.isPrivate else { return }
        var offers: [AutofillSaveOffer.Item] = []
        if let card, let parsed = parseCard(card), !AutofillStore.shared.knowsCard(last4: String(parsed.number.suffix(4)),
                                                                                    expMonth: parsed.month, expYear: parsed.year) {
            offers.append(.card(number: parsed.number, name: card["cardName"] ?? "", month: parsed.month, year: parsed.year))
        }
        if let address, let parsed = parseAddress(address), !AutofillStore.shared.knows(parsed) { offers.append(.address(parsed)) }
        if !offers.isEmpty { AutofillSavePresenter.shared.offer(offers, in: controller) }
    }

    static func parseCard(_ fields: [String: String]) -> (number: String, month: Int, year: Int)? {
        let digits = (fields["cardNumber"] ?? "").filter(\.isNumber)
        guard AutofillStore.isCardNumber(digits) else { return nil }
        var month = Int(fields["cardExpMonth"]?.filter(\.isNumber) ?? "") ?? 0
        var year = Int(fields["cardExpYear"]?.filter(\.isNumber) ?? "") ?? 0
        if let expiry = fields["cardExpiry"] {
            let parts = expiry.split { !$0.isNumber }.compactMap { Int($0) }
            if parts.count >= 2 { month = parts[0]; year = parts[1] }
        }
        return (digits, (1...12).contains(month) ? month : 0, AutofillStore.fullYear(year))
    }

    static func parseAddress(_ fields: [String: String]) -> AutofillAddress? {
        var address = AutofillAddress()
        address.name = fields["name"] ?? [fields["givenName"], fields["familyName"]].compactMap { $0 }.joined(separator: " ")
        address.organization = fields["organization"] ?? ""
        address.street = fields["line1"] ?? fields["street"]?.components(separatedBy: .newlines).first ?? ""
        address.line2 = fields["line2"] ?? ""
        address.city = fields["city"] ?? ""
        address.region = fields["region"] ?? ""
        address.postalCode = fields["postalCode"] ?? ""
        address.country = fields["country"] ?? ""
        address.email = fields["email"] ?? ""
        address.phone = fields["phone"] ?? ""
        guard !address.street.isEmpty, !address.postalCode.isEmpty || !address.city.isEmpty else { return nil }
        return address
    }
}
