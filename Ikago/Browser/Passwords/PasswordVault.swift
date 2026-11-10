import CryptoKit
import Foundation
import LocalAuthentication
import Security

/// Ikago's own password store, separate from Apple Passwords and readable only by Ikago.
///
/// Every password is encrypted to a Secure Enclave key that only works after Touch ID (or your Mac
/// password) for that one use, so even Ikago can't read a password without you, and a copy of the file
/// is useless on any other Mac. Sites and usernames are encrypted with `SealedStorage`, and the file
/// lives in protected storage. Importing only needs the public key, so it never asks for Touch ID.
@MainActor @Observable
final class PasswordVault {
    static let shared = PasswordVault()

    struct Login: Codable, Identifiable, Equatable, Sendable {
        let id: UUID
        /// Lowercased host without "www.", used for matching.
        var site: String
        var title: String?
        var username: String
        /// Ephemeral P-256 public key (65 bytes) then AES-GCM sealed box, bound to site and username.
        var secret: Data
        var created: Double
        var lastUsed: Double?
    }

    struct Failure: LocalizedError {
        let errorDescription: String?
    }

    private struct File: Codable {
        var version = 1
        /// The Secure Enclave key, encrypted by the enclave itself (unusable on another Mac). Checks
        /// store a software key here instead.
        var key: Data
        var logins: [Login]
    }

    private(set) var logins: [Login] = [] { didSet { indexByDomain() } }
    /// Registrable domain → indexes into `logins`, so a page load looks its site up instead of scanning.
    @ObservationIgnored private var byDomain: [String: [Int]] = [:]
    private var key: Data?
    private var loaded = false
    /// When opening an existing vault last failed; page loads retry only after `retryInterval`.
    @ObservationIgnored private var failedLoad: Date?
    private static let retryInterval: TimeInterval = 60
    /// A vault file exists but couldn't be opened. Nothing may be saved over it then, or a new key
    /// would replace the one its passwords need.
    private(set) var loadIssue: String?
    private let directory: URL
    private let usesTestKey: Bool

    init(directory: URL = SessionStore.standard.directory, usesTestKey: Bool = SealedStorage.usesTestKey) {
        self.directory = directory
        self.usesTestKey = usesTestKey
    }

    private var file: URL { directory.appending(path: "passwords.vault") }
    private var backup: URL { directory.appending(path: "passwords.backup.vault") }

    var isEmpty: Bool { loadIfNeeded(); return logins.isEmpty }

    /// `force` retries a vault that failed to open at once (Settings, or a change the person asked for);
    /// otherwise a failure is retried at most once a minute, not on every page load.
    func loadIfNeeded(force: Bool = false) {
        guard !loaded else { return }
        if !force, let failedLoad, Date().timeIntervalSince(failedLoad) < Self.retryInterval { return }
        var found = false
        for url in [file, backup] where FileManager.default.fileExists(atPath: url.path) {
            found = true
            guard let data = try? Data(contentsOf: url), let plain = try? SealedStorage.open(data),
                  let stored = try? JSONDecoder().decode(File.self, from: plain) else { continue }
            key = stored.key
            logins = stored.logins
            loaded = true
            loadIssue = nil
            failedLoad = nil
            return
        }
        // Tried again later: a locked Keychain may only be passing.
        loadIssue = found ? "Ikago’s saved passwords couldn’t be opened, so nothing was changed." : nil
        loaded = !found
        failedLoad = found ? Date() : nil
    }

    private func indexByDomain() {
        byDomain = [:]
        for (index, login) in logins.enumerated() { byDomain[PublicSuffix.registrableDomain(login.site), default: []].append(index) }
    }

    private func requireReadable() throws {
        loadIfNeeded(force: true)
        if let loadIssue { throw Failure(errorDescription: loadIssue) }
    }

    /// Saved logins for a page's host: every login on the same registrable domain
    /// (accounts.google.com also offers mail.google.com and google.com), never another site. Subdomains
    /// of a public suffix such as github.io are separate sites. The exact host comes first, then
    /// parents and children, then other subdomains; each group by most recently used.
    func matches(for host: String) -> [Login] {
        loadIfNeeded()
        let host = Self.site(host)
        guard !host.isEmpty else { return [] }
        // Only logins on the same registrable domain, from the index.
        let candidates = (byDomain[PublicSuffix.registrableDomain(host)] ?? []).map { logins[$0] }
        func rank(_ site: String) -> Int {
            if site == host { return 0 }
            return host.hasSuffix("." + site) || site.hasSuffix("." + host) ? 1 : 2
        }
        return candidates.map { ($0, rank($0.site)) }
            .sorted { ($0.1, -($0.0.lastUsed ?? 0), -$0.0.created) < ($1.1, -($1.0.lastUsed ?? 0), -$1.0.created) }
            .map(\.0)
    }

    // MARK: Changing

    struct NewLogin: Equatable, Sendable {
        var url: String, title: String?, username: String, password: String
    }

    /// Adds logins, replacing any with the same site and username. Returns how many were stored.
    @discardableResult
    func add(_ new: [NewLogin]) throws -> Int {
        try requireReadable()
        let publicKey = try vaultPublicKey()
        var updated = logins
        var count = 0
        for entry in new {
            let site = Self.site(URL(string: entry.url)?.host ?? entry.url)
            guard !site.isEmpty, !entry.password.isEmpty else { continue }
            let secret = try Self.encrypt(entry.password, to: publicKey, site: site, username: entry.username)
            updated.removeAll { $0.site == site && $0.username == entry.username }
            updated.append(Login(id: UUID(), site: site, title: entry.title, username: entry.username, secret: secret,
                                 created: Date().timeIntervalSince1970))
            count += 1
        }
        try save(updated)
        return count
    }

    func delete(_ ids: Set<UUID>) throws {
        try requireReadable()
        try save(logins.filter { !ids.contains($0.id) })
    }

    /// Removes every login and the enclave key with them.
    func deleteAll() throws {
        for url in [file, backup] { try? FileManager.default.removeItem(at: url) }
        logins = []
        key = nil
        loaded = true
        loadIssue = nil
    }

    private func save(_ updated: [Login]) throws {
        guard let key else { throw Failure(errorDescription: "The password vault has no key.") }
        let data = try SealedStorage.seal(JSONEncoder().encode(File(key: key, logins: updated)))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if FileManager.default.fileExists(atPath: file.path) {
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.copyItem(at: file, to: backup)
        }
        try data.write(to: file, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        if updated.isEmpty { try? FileManager.default.removeItem(at: backup) }
        logins = updated
    }

    // MARK: Reading a password

    /// Asks for Touch ID (or the Mac's password) for this one use, then decrypts. Never cached.
    func password(for login: Login, reason: String) async throws -> String {
        loadIfNeeded(force: true)
        guard let key, let current = logins.first(where: { $0.id == login.id }) else {
            throw Failure(errorDescription: "This password is no longer saved.")
        }
        let password: String
        if usesTestKey {
            password = try Self.decrypt(current, with: P256.KeyAgreement.PrivateKey(rawRepresentation: key))
        } else {
            let context = LAContext()
            context.touchIDAuthenticationAllowableReuseDuration = 0
            do { try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) } catch {
                throw Failure(errorDescription: nil)  // cancelled or failed: nothing to report
            }
            defer { context.invalidate() }
            let enclaveKey = try SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: key, authenticationContext: context)
            password = try Self.decrypt(current, with: enclaveKey)
        }
        if let index = logins.firstIndex(where: { $0.id == login.id }) {
            var updated = logins
            updated[index].lastUsed = Date().timeIntervalSince1970
            try? save(updated)
        }
        return password
    }

    // MARK: Keys and encryption

    private func vaultPublicKey() throws -> P256.KeyAgreement.PublicKey {
        if let key {
            return usesTestKey ? try P256.KeyAgreement.PrivateKey(rawRepresentation: key).publicKey
                               : try SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: key).publicKey
        }
        if usesTestKey {
            let created = P256.KeyAgreement.PrivateKey()
            key = created.rawRepresentation
            return created.publicKey
        }
        guard SecureEnclave.isAvailable else {
            throw Failure(errorDescription: "Ikago’s password vault needs a Mac with a Secure Enclave (Touch ID or Apple silicon).")
        }
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                                                           [.privateKeyUsage, .userPresence], &error) else {
            throw error!.takeRetainedValue() as Error
        }
        let created = try SecureEnclave.P256.KeyAgreement.PrivateKey(accessControl: access)
        key = created.dataRepresentation
        return created.publicKey
    }

    nonisolated private static let info = Data("ikago-password-v1".utf8)

    nonisolated private static func associatedData(site: String, username: String) -> Data { Data((site + "\n" + username).utf8) }

    nonisolated static func encrypt(_ password: String, to publicKey: P256.KeyAgreement.PublicKey, site: String, username: String) throws -> Data {
        let ephemeral = P256.KeyAgreement.PrivateKey()
        let shared = try ephemeral.sharedSecretFromKeyAgreement(with: publicKey)
        let ephemeralKey = ephemeral.publicKey.x963Representation
        let symmetric = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: ephemeralKey, sharedInfo: info, outputByteCount: 32)
        let box = try AES.GCM.seal(Data(password.utf8), using: symmetric, authenticating: associatedData(site: site, username: username))
        guard let combined = box.combined else { throw Failure(errorDescription: "A password couldn’t be encrypted.") }
        return ephemeralKey + combined
    }

    private static func decrypt(_ login: Login, with agree: (P256.KeyAgreement.PublicKey) throws -> SharedSecret) throws -> String {
        guard login.secret.count > 65 else { throw Failure(errorDescription: "This saved password is damaged.") }
        let ephemeralKey = login.secret.prefix(65)
        let shared = try agree(P256.KeyAgreement.PublicKey(x963Representation: ephemeralKey))
        let symmetric = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: ephemeralKey, sharedInfo: info, outputByteCount: 32)
        let box = try AES.GCM.SealedBox(combined: login.secret.dropFirst(65))
        let plain = try AES.GCM.open(box, using: symmetric, authenticating: associatedData(site: login.site, username: login.username))
        return String(decoding: plain, as: UTF8.self)
    }

    private static func decrypt(_ login: Login, with key: P256.KeyAgreement.PrivateKey) throws -> String {
        try decrypt(login) { try key.sharedSecretFromKeyAgreement(with: $0) }
    }

    private static func decrypt(_ login: Login, with key: SecureEnclave.P256.KeyAgreement.PrivateKey) throws -> String {
        try decrypt(login) { try key.sharedSecretFromKeyAgreement(with: $0) }
    }

    /// "WWW.Example.com." → "example.com".
    nonisolated static func site(_ host: String) -> String {
        var host = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }
}
