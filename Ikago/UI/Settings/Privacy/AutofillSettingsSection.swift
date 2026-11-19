import SwiftUI

/// Settings ▸ Autofill: whether addresses and cards fill and are offered for saving, and the saved ones, each to edit or
/// remove. A card shows only its brand, last four digits and expiry; its number is never shown or edited here.
struct AutofillSettingsSection: View {
    @Bindable var state: BrowserState
    private var store: AutofillStore { .shared }
    @State private var editingAddress: AutofillAddress?
    @State private var editingCard: CardDraft?
    @State private var error: String?

    var body: some View {
        let _ = store.loadIfNeeded()
        PageSection(title: "Autofill", footer: "Saved on this Mac only, encrypted. Card numbers open with Touch ID or your Mac password for each fill, and security codes are never saved. Forms on plain HTTP pages are never filled.") {
            toggle("Fill addresses", subtitle: "Suggest saved addresses in address and contact forms", \.autofillAddresses)
            PageDivider()
            toggle("Fill cards", subtitle: "Suggest saved cards at checkout, with Touch ID for each", \.autofillCards)
            PageDivider()
            toggle("Offer to save", subtitle: "After you submit a form with a new address or card", \.autofillOfferSave)
        }
        PageSection(title: "Addresses") {
            if store.addresses.isEmpty {
                PageRow(title: "No saved addresses", subtitle: "Add one, or save it when you next fill in an address") { EmptyView() }
            }
            ForEach(store.orderedAddressesForSettings) { address in
                PageRow(title: address.title, subtitle: [address.summary, address.email].filter { !$0.isEmpty }.joined(separator: " · ")) {
                    HStack(spacing: 8) {
                        Button("Edit") { editingAddress = address }.buttonStyle(SettingsButtonStyle())
                        Button("Remove") { run { try store.delete(address: address.id) } }.buttonStyle(SettingsButtonStyle())
                    }
                }
                PageDivider()
            }
            PageRow(title: "Add Address") {
                Button("Add…") { editingAddress = AutofillAddress() }.buttonStyle(SettingsButtonStyle())
            }
        }
        PageSection(title: "Cards") {
            if store.cards.isEmpty {
                PageRow(title: "No saved cards", subtitle: "Add one, or save it when you next pay for something") { EmptyView() }
            }
            ForEach(store.cards) { card in
                PageRow(title: card.title, subtitle: [card.name, card.expiry.isEmpty ? "" : (card.isExpired ? "Expired " : "Expires ") + card.expiry]
                            .filter { !$0.isEmpty }.joined(separator: " · ")) {
                    HStack(spacing: 8) {
                        Button("Edit") { editingCard = CardDraft(card) }.buttonStyle(SettingsButtonStyle())
                        Button("Remove") { run { try store.delete(card: card.id) } }.buttonStyle(SettingsButtonStyle())
                    }
                }
                PageDivider()
            }
            PageRow(title: "Add Card") {
                Button("Add…") { editingCard = CardDraft(nil) }.buttonStyle(SettingsButtonStyle())
            }
            if let error { Text(error).font(.system(size: 11)).foregroundStyle(.orange).padding(.horizontal, 16).padding(.bottom, 8) }
        }
        .sheet(item: $editingAddress) { address in
            AddressEditor(address: address, colors: state.palette) { saved in
                run { try store.save(saved) }
                editingAddress = nil
            } cancel: { editingAddress = nil }
        }
        .sheet(item: $editingCard) { draft in
            CardEditor(draft: draft, colors: state.palette) { result in
                editingCard = nil
                run {
                    if let card = result.existing {
                        var updated = card
                        updated.name = result.name; updated.expMonth = result.month; updated.expYear = AutofillStore.fullYear(result.year)
                        updated.nickname = result.nickname
                        try store.update(updated)
                    } else {
                        try store.saveCard(number: result.number, name: result.name, expMonth: result.month, expYear: result.year,
                                           nickname: result.nickname)
                    }
                }
            } cancel: { editingCard = nil }
        }
    }

    private func toggle(_ title: String, subtitle: String, _ path: WritableKeyPath<BrowserPreferences, Bool?>) -> some View {
        PageRow(title: title, subtitle: subtitle) {
            Toggle(title, isOn: Binding(get: { state.browserPreferences[keyPath: path] ?? true },
                                        set: { state.browserPreferences[keyPath: path] = $0 }))
                .labelsHidden().toggleStyle(.switch)
        }
    }

    private func run(_ body: () throws -> Void) {
        do { try body(); error = nil } catch { self.error = (error as? LocalizedError)?.errorDescription ?? "That couldn’t be saved." }
    }
}

extension AutofillStore {
    /// Settings lists addresses by name.
    var orderedAddressesForSettings: [AutofillAddress] { addresses.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending } }
}

/// A card being added (a number to enter) or edited (only its name, expiry and nickname).
struct CardDraft: Identifiable {
    let id = UUID()
    let existing: AutofillCard?
    var number = ""
    var name: String
    var month: Int
    var year: Int
    var nickname: String

    init(_ card: AutofillCard?) {
        existing = card
        name = card?.name ?? ""
        month = card?.expMonth ?? 0
        year = card?.expYear ?? 0
        nickname = card?.nickname ?? ""
    }
}

private struct AddressEditor: View {
    @State var address: AutofillAddress
    let colors: Palette
    let save: (AutofillAddress) -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(address.isEmpty ? "Add Address" : "Edit Address").font(.system(size: 15, weight: .semibold))
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                row("Name", $address.name)
                row("Company", $address.organization)
                row("Street", $address.street)
                row("Apt, suite", $address.line2)
                GridRow {
                    label("City")
                    HStack(spacing: 8) {
                        TextField("City", text: $address.city).modalInput(colors)
                        TextField("State or region", text: $address.region).modalInput(colors)
                    }
                }
                GridRow {
                    label("Postal code")
                    HStack(spacing: 8) {
                        TextField("Postal code", text: $address.postalCode).modalInput(colors)
                        TextField("Country", text: $address.country).modalInput(colors)
                    }
                }
                row("Email", $address.email)
                row("Phone", $address.phone)
            }
            HStack {
                Spacer()
                Button("Cancel", action: cancel).buttonStyle(SettingsButtonStyle()).keyboardShortcut(.cancelAction)
                Button("Save") { save(address) }.buttonStyle(SettingsButtonStyle(prominent: true)).keyboardShortcut(.defaultAction)
                    .disabled(address.isEmpty)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 460)
    }

    private func row(_ title: String, _ text: Binding<String>) -> some View {
        GridRow {
            label(title)
            TextField(title, text: text).modalInput(colors)
        }
    }

    private func label(_ title: String) -> some View {
        Text(title).font(.system(size: 12)).foregroundStyle(colors.secondary).gridColumnAlignment(.trailing)
    }
}

private struct CardEditor: View {
    @State var draft: CardDraft
    let colors: Palette
    let save: (CardDraft) -> Void
    let cancel: () -> Void

    private var digits: String { draft.number.filter(\.isNumber) }
    private var valid: Bool {
        (draft.existing != nil || AutofillStore.isCardNumber(digits)) && (1...12).contains(draft.month) && draft.year > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(draft.existing == nil ? "Add Card" : "Edit Card").font(.system(size: 15, weight: .semibold))
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    label("Number")
                    if let card = draft.existing {
                        Text(card.title).font(.system(size: 13)).foregroundStyle(colors.secondary)
                    } else {
                        TextField("Card number", text: $draft.number).modalInput(colors).font(.system(size: 13, design: .monospaced))
                    }
                }
                GridRow {
                    label("Name on card")
                    TextField("Name on card", text: $draft.name).modalInput(colors)
                }
                GridRow {
                    label("Expires")
                    HStack(spacing: 8) {
                        Picker("Month", selection: $draft.month) {
                            Text("Month").tag(0)
                            ForEach(1...12, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                        }
                        .labelsHidden().frame(width: 100)
                        Picker("Year", selection: $draft.year) {
                            Text("Year").tag(0)
                            let now = Calendar.current.component(.year, from: Date())
                            ForEach(Array(Set([draft.year].filter { $0 > 0 } + Array(now...(now + 15)))).sorted(), id: \.self) { Text(String($0)).tag($0) }
                        }
                        .labelsHidden().frame(width: 100)
                    }
                }
                GridRow {
                    label("Nickname")
                    TextField("Optional", text: $draft.nickname).modalInput(colors)
                }
            }
            if draft.existing == nil, !digits.isEmpty, !AutofillStore.isCardNumber(digits) {
                Text("Check the card number.").font(.system(size: 11)).foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button("Cancel", action: cancel).buttonStyle(SettingsButtonStyle()).keyboardShortcut(.cancelAction)
                Button("Save") { save(draft) }.buttonStyle(SettingsButtonStyle(prominent: true)).keyboardShortcut(.defaultAction)
                    .disabled(!valid)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 420)
    }

    private func label(_ title: String) -> some View {
        Text(title).font(.system(size: 12)).foregroundStyle(colors.secondary).gridColumnAlignment(.trailing)
    }
}
