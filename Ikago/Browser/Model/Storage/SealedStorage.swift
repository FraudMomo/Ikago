import CryptoKit
import Foundation
import os
import Security

/// Encrypts history, sessions, download history and favicons at rest with AES-GCM. The key lives in
/// the login Keychain, readable only by Ikago's signature. So copying these files (a backup, another
/// app in your account) reveals nothing without Keychain access. It never falls back to plain text.
enum SealedStorage {
    enum Failure: LocalizedError {
        case keychainUnavailable(OSStatus)
        var errorDescription: String? {
            switch self {
            case .keychainUnavailable(let status):
                "macOS didn’t give Ikago its encryption key (\(SecCopyErrorMessageString(status, nil) as String? ?? "error \(status)"))."
            }
        }
    }

    private static let magic = Data("IKSEAL1\n".utf8)
    private static let service = "app.ikago.browser.storage"
    private static let account = "local-data-key"
    private static let cachedKey = OSAllocatedUnfairLock<SymmetricKey?>(initialState: nil)

    static func isSealed(_ data: Data) -> Bool { data.starts(with: magic) }

    static func seal(_ data: Data) throws -> Data {
        guard let combined = try AES.GCM.seal(data, using: key()).combined else { throw CocoaError(.fileWriteUnknown) }
        return magic + combined
    }

    /// Files from before encryption are returned as they are, and become encrypted on their next save.
    static func open(_ data: Data) throws -> Data {
        guard isSealed(data) else { return data }
        return try AES.GCM.open(AES.GCM.SealedBox(combined: data.dropFirst(magic.count)), using: key())
    }

    /// Checked once at launch, so a locked Keychain can be retried instead of looking like lost data.
    static func prepare() throws { _ = try key() }

    private static func key() throws -> SymmetricKey {
        if let key = cachedKey.withLock({ $0 }) { return key }
        let key = try usesTestKey ? SymmetricKey(data: SHA256.hash(data: Data("ikago-test-key".utf8))) : keychainKey()
        cachedKey.withLock { $0 = key }
        return key
    }

    /// Unattended checks use disposable data, and must never touch the real Keychain or raise a prompt.
    static var usesTestKey: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["IKAGO_TEST_MODE"] != nil { return true }
        #endif
        #if IKAGO_CHECKS
        if CommandLine.arguments.contains("--cef-smoke") { return true }
        #endif
        return false
    }

    private static func keychainKey() throws -> SymmetricKey {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query.merging([kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne]) { $1 } as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data, data.count == 32 { return SymmetricKey(data: data) }
        guard status == errSecItemNotFound else { throw Failure.keychainUnavailable(status) }
        let key = SymmetricKey(size: .bits256)
        let attributes = query.merging([kSecValueData: key.withUnsafeBytes { Data($0) }, kSecAttrLabel: "Ikago local data key",
                                        kSecAttrDescription: "Encrypts Ikago's history and session"]) { $1 }
        let added = SecItemAdd(attributes as CFDictionary, nil)
        guard added == errSecSuccess else { throw Failure.keychainUnavailable(added) }
        return key
    }
}
