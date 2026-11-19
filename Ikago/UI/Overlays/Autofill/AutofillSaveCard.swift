import SwiftUI

/// What the save card shows. A card's number stays with the presenter, outside observed state, until it is saved or
/// the card goes away.
struct AutofillSaveOffer: Equatable {
    enum Item: Equatable {
        case address(AutofillAddress)
        case card(number: String, name: String, month: Int, year: Int)
    }

    let id = UUID()
    let card: Bool
    let title: String
    let detail: String
}

/// Offers to save what a submitted form held, one at a time: the card first, then the address. Nothing is saved without
/// the person's choice, and the card goes away on its own after a while.
@MainActor
final class AutofillSavePresenter {
    static let shared = AutofillSavePresenter()
    private var queue: [AutofillSaveOffer.Item] = []
    private var current: AutofillSaveOffer.Item?
    private weak var chrome: ChromeModel?
    private var expiry: Task<Void, Never>?

    func offer(_ items: [AutofillSaveOffer.Item], in controller: BrowserWindowController) {
        dismissAll()
        chrome = controller.chrome
        queue = items
        showNext()
    }

    private func showNext() {
        expiry?.cancel()
        guard !queue.isEmpty else { current = nil; chrome?.autofillSave = nil; return }
        let item = queue.removeFirst()
        current = item
        switch item {
        case .address(let address):
            chrome?.autofillSave = AutofillSaveOffer(card: false, title: address.title, detail: address.summary)
        case .card(let number, let name, let month, let year):
            let brand = AutofillStore.brand(of: number)
            let expiry = month > 0 ? String(format: " · %02d/%02d", month, year % 100) : ""
            chrome?.autofillSave = AutofillSaveOffer(card: true, title: "\(brand.isEmpty ? "Card" : brand) •••• \(number.suffix(4))",
                                                     detail: name + expiry)
        }
        expiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(45))
            if !Task.isCancelled { self?.dismissAll() }
        }
    }

    /// Saves the one on screen, then shows the next. Returns an error to show, if any.
    func save() -> String? {
        guard let current else { return nil }
        do {
            switch current {
            case .address(let address): try AutofillStore.shared.save(address)
            case .card(let number, let name, let month, let year):
                try AutofillStore.shared.saveCard(number: number, name: name, expMonth: month, expYear: year)
            }
            showNext()
            return nil
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? "It couldn’t be saved."
        }
    }

    func notNow() { showNext() }

    func dismissAll() {
        expiry?.cancel()
        expiry = nil
        queue = []
        current = nil
        chrome?.autofillSave = nil
    }
}

/// "Save this card?" or "Save this address?" after a form is submitted.
struct AutofillSaveCard: View {
    let offer: AutofillSaveOffer
    let colors: Palette
    @State private var error: String?
    private var presenter: AutofillSavePresenter { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: offer.card ? "creditcard.fill" : "house.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(LinearGradient(colors: [(offer.card ? Color.indigo : Color.teal).opacity(0.85),
                                                                       offer.card ? Color.indigo : Color.teal],
                                                             startPoint: .top, endPoint: .bottom)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(offer.card ? "Save this card?" : "Save this address?").font(.system(size: 13, weight: .semibold))
                    Text(offer.title).font(.system(size: 11.5)).foregroundStyle(colors.text).lineLimit(1)
                    if !offer.detail.isEmpty {
                        Text(offer.detail).font(.system(size: 11)).foregroundStyle(colors.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                ChromeButton(symbol: "xmark", help: "Not Now", colors: colors, size: 22, glass: false) { presenter.dismissAll() }
            }
            Text(offer.card ? "Saved on this Mac and encrypted. Each fill asks for Touch ID; the security code is never saved."
                 : "Saved on this Mac and encrypted, to fill forms like this one.")
                .font(.system(size: 11)).foregroundStyle(colors.secondary).fixedSize(horizontal: false, vertical: true)
            if let error { Text(error).font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            HStack(spacing: 8) {
                Spacer()
                Button("Not Now") { presenter.notNow() }.buttonStyle(SettingsButtonStyle())
                Button("Save") { error = presenter.save() }.buttonStyle(SettingsButtonStyle(prominent: true))
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 300)
        .foregroundStyle(colors.text)
        .modalSurface(colors, radius: Radius.card)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(offer.card ? "Save card \(offer.title)" : "Save address \(offer.title)")
    }
}
