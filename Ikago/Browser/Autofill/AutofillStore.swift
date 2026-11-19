import Foundation
import Observation

/// A saved address for filling forms.
struct AutofillAddress: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var name = ""
    var organization = ""
    var street = ""
    var line2 = ""
    var city = ""
    var region = ""
    var postalCode = ""
    var country = ""
    var email = ""
    var phone = ""
    var lastUsed: Double?

    /// The name, or else the first thing it has.
    var title: String { [name, organization, street, email].first { !$0.isEmpty } ?? "Address" }
    /// One line under the title: where it is.
    var summary: String { [street, city, postalCode].filter { !$0.isEmpty }.joined(separator: ", ") }
    var isEmpty: Bool { [name, organization, street, line2, city, region, postalCode, country, email, phone].allSatisfy(\.isEmpty) }

    /// The parts a page's fields ask for, by `AutofillField` name.
    var values: [String: String] {
        let parts = name.split(separator: " ")
        let given = parts.count > 1 ? parts.dropLast().joined(separator: " ") : name
        let family = parts.count > 1 ? String(parts.last!) : ""
        return ["name": name, "givenName": given, "familyName": family, "organization": organization,
                "street": [street, line2].filter { !$0.isEmpty }.joined(separator: "\n"), "line1": street, "line2": line2,
                "city": city, "region": region, "postalCode": postalCode, "country": country, "email": email, "phone": phone]
    }

    /// Whether `other` is the same address, so saving it again changes nothing.
    func matches(_ other: AutofillAddress) -> Bool {
        func key(_ text: String) -> String { text.lowercased().filter { $0.isLetter || $0.isNumber } }
        return key(street) == key(other.street) && key(postalCode) == key(other.postalCode) && key(name) == key(other.name)
    }
}

/// A saved payment card. The number is sealed to the vault's Secure Enclave key and opens only with Touch ID for each
/// fill; the security code is never saved.
struct AutofillCard: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var name = ""
    var expMonth = 0
    var expYear = 0
    var last4 = ""
    var brand = ""
    var number: Data
    var nickname = ""
    var lastUsed: Double?

    var title: String { nickname.isEmpty ? "\(brand.isEmpty ? "Card" : brand) •••• \(last4)" : nickname }
    var expiry: String { expMonth > 0 ? String(format: "%02d/%02d", expMonth, expYear % 100) : "" }
    var isExpired: Bool {
        let now = Calendar.current.dateComponents([.year, .month], from: Date())
        guard expYear > 0, let year = now.year, let month = now.month else { return false }
        return expYear < year || (expYear == year && expMonth < month)
    }
}

/// Addresses and payment cards for filling forms (Settings ▸ Autofill), in one file encrypted at rest
/// (`SealedStorage`). Card numbers are sealed again to the password vault's key (`PasswordVault.seal`).
@MainActor @Observable
final class AutofillStore {
    static let shared = AutofillStore()

    private struct File: Codable {
        var version = 1
        var addresses: [AutofillAddress] = []
        var cards: [AutofillCard] = []
    }

    private(set) var addresses: [AutofillAddress] = []
    private(set) var cards: [AutofillCard] = []
    @ObservationIgnored private var loaded = false
    /// The file exists but couldn't be opened: nothing is written over it.
    private(set) var loadIssue: String?
    @ObservationIgnored private let directory: URL

    init(directory: URL = SessionStore.standard.directory) { self.directory = directory }

    private var file: URL { directory.appending(path: "autofill.sealed") }
    private var backup: URL { directory.appending(path: "autofill.backup.sealed") }

    var hasCards: Bool { loadIfNeeded(); return !cards.isEmpty }

    func loadIfNeeded() {
        guard !loaded else { return }
        var found = false
        for url in [file, backup] where FileManager.default.fileExists(atPath: url.path) {
            found = true
            guard let data = try? Data(contentsOf: url), let plain = try? SealedStorage.open(data),
                  let stored = try? JSONDecoder().decode(File.self, from: plain) else { continue }
            addresses = stored.addresses
            cards = stored.cards
            loaded = true
            loadIssue = nil
            return
        }
        loadIssue = found ? "Ikago’s saved addresses and cards couldn’t be opened, so nothing was changed." : nil
        loaded = !found
    }

    private func write(addresses: [AutofillAddress], cards: [AutofillCard]) throws {
        loadIfNeeded()
        if let loadIssue { throw PasswordVault.Failure(errorDescription: loadIssue) }
        let data = try SealedStorage.seal(JSONEncoder().encode(File(addresses: addresses, cards: cards)))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if FileManager.default.fileExists(atPath: file.path) {
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.copyItem(at: file, to: backup)
        }
        try data.write(to: file, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        self.addresses = addresses
        self.cards = cards
    }

    // MARK: Addresses

    /// Adds an address, or replaces the one with its id.
    func save(_ address: AutofillAddress) throws {
        loadIfNeeded()
        guard !address.isEmpty else { return }
        var list = addresses.filter { $0.id != address.id }
        list.append(address)
        try write(addresses: list, cards: cards)
    }

    func delete(address id: UUID) throws {
        loadIfNeeded()
        try write(addresses: addresses.filter { $0.id != id }, cards: cards)
    }

    func knows(_ address: AutofillAddress) -> Bool { loadIfNeeded(); return addresses.contains { $0.matches(address) } }

    // MARK: Cards

    /// Saves a card from its full number (sealed to the vault's key; only the last four digits stay readable).
    func saveCard(number: String, name: String, expMonth: Int, expYear: Int, nickname: String = "", replacing id: UUID? = nil) throws {
        loadIfNeeded()
        let digits = number.filter(\.isNumber)
        guard Self.isCardNumber(digits) else { throw PasswordVault.Failure(errorDescription: "That isn’t a valid card number.") }
        let cardID = id ?? UUID()
        let sealed = try PasswordVault.shared.seal(secret: digits, label: cardID.uuidString)
        let card = AutofillCard(id: cardID, name: name, expMonth: expMonth, expYear: Self.fullYear(expYear), last4: String(digits.suffix(4)),
                                brand: Self.brand(of: digits), number: sealed, nickname: nickname)
        try write(addresses: addresses, cards: cards.filter { $0.id != cardID } + [card])
    }

    /// Changes a card's name, expiry or nickname; the number stays as it is.
    func update(_ card: AutofillCard) throws {
        loadIfNeeded()
        try write(addresses: addresses, cards: cards.map { $0.id == card.id ? card : $0 })
    }

    func delete(card id: UUID) throws {
        loadIfNeeded()
        try write(addresses: addresses, cards: cards.filter { $0.id != id })
    }

    func knowsCard(last4: String, expMonth: Int, expYear: Int) -> Bool {
        loadIfNeeded()
        return cards.contains { $0.last4 == last4 && $0.expMonth == expMonth && $0.expYear == Self.fullYear(expYear) }
    }

    /// The card's full number, after Touch ID (or the Mac's password) for this one fill.
    func number(of card: AutofillCard, reason: String) async throws -> String {
        try await PasswordVault.shared.open(secret: card.number, label: card.id.uuidString, reason: reason)
    }

    func markUsed(address id: UUID) {
        guard let index = addresses.firstIndex(where: { $0.id == id }) else { return }
        var list = addresses
        list[index].lastUsed = Date().timeIntervalSince1970
        try? write(addresses: list, cards: cards)
    }

    func markUsed(card id: UUID) {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }
        var list = cards
        list[index].lastUsed = Date().timeIntervalSince1970
        try? write(addresses: addresses, cards: list)
    }

    /// Recently used first.
    var orderedAddresses: [AutofillAddress] { loadIfNeeded(); return addresses.sorted { ($0.lastUsed ?? 0) > ($1.lastUsed ?? 0) } }
    var orderedCards: [AutofillCard] { loadIfNeeded(); return cards.filter { !$0.isExpired }.sorted { ($0.lastUsed ?? 0) > ($1.lastUsed ?? 0) } }

    #if DEBUG || IKAGO_CHECKS
    func deleteAllForChecks() throws { try write(addresses: [], cards: []) }
    #endif

    // MARK: Card numbers

    /// 12 to 19 digits that pass the Luhn check.
    nonisolated static func isCardNumber(_ digits: String) -> Bool {
        guard (12...19).contains(digits.count), digits.allSatisfy(\.isNumber) else { return false }
        var sum = 0
        for (index, character) in digits.reversed().enumerated() {
            var value = character.wholeNumberValue ?? 0
            if index % 2 == 1 { value *= 2; if value > 9 { value -= 9 } }
            sum += value
        }
        return sum % 10 == 0
    }

    nonisolated static func brand(of digits: String) -> String {
        func starts(_ prefixes: [String]) -> Bool { prefixes.contains { digits.hasPrefix($0) } }
        if digits.hasPrefix("4") { return "Visa" }
        if starts(["51", "52", "53", "54", "55"]) || (Int(digits.prefix(4)).map { (2221...2720).contains($0) } ?? false) { return "Mastercard" }
        if starts(["34", "37"]) { return "American Express" }
        if starts(["6011", "65"]) || (Int(digits.prefix(3)).map { (644...649).contains($0) } ?? false) { return "Discover" }
        if (Int(digits.prefix(4)).map { (3528...3589).contains($0) } ?? false) { return "JCB" }
        if starts(["62"]) { return "UnionPay" }
        if starts(["36", "300", "301", "302", "303", "304", "305", "38"]) { return "Diners Club" }
        return ""
    }

    /// "27" → 2027.
    nonisolated static func fullYear(_ year: Int) -> Int { year > 0 && year < 100 ? 2000 + year : year }
}
