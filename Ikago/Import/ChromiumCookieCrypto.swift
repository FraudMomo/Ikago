import Foundation
import Security
import LocalAuthentication
import CommonCrypto
import CryptoKit

/// Chromium's macOS v10 scheme. Keychain access occurs only after an explicit import choice.
enum ChromiumCookieCrypto {
    enum Browser: String, CaseIterable, Identifiable, Sendable {
        case chrome = "Chrome", edge = "Microsoft Edge", brave = "Brave", chromium = "Chromium", vivaldi = "Vivaldi", arc = "Arc"
        var id: String { rawValue }
        var service: String { rawValue + " Safe Storage" }
    }

    static func key(for browser: Browser) throws -> Data {
        let authentication = LAContext()
        authentication.localizedReason = "Import selected browser cookies into Ikago"
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: browser.service,
                                    kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne,
                                    kSecUseAuthenticationContext: authentication]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let password = item as? Data else {
            throw ImportFileParser.error("Cookie decryption was not authorized or the selected browser’s Safe Storage key is unavailable. Other data can still be imported.")
        }
        return try derive(password: password)
    }

    static func derive(password: Data) throws -> Data {
        var output = [UInt8](repeating: 0, count: 16)
        let salt = Array("saltysalt".utf8)
        let status = password.withUnsafeBytes { secret in
            CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), secret.bindMemory(to: Int8.self).baseAddress, password.count,
                                salt, salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003, &output, output.count)
        }
        guard status == kCCSuccess else { throw ImportFileParser.error("The cookie key could not be derived.") }
        return Data(output)
    }

    static func decrypt(_ encrypted: Data, key: Data, domain: String, databaseVersion: Int) -> String? {
        guard encrypted.starts(with: Array("v10".utf8)), key.count == 16 else { return nil }
        let ciphertext = Data(encrypted.dropFirst(3))
        var output = [UInt8](repeating: 0, count: ciphertext.count + kCCBlockSizeAES128)
        let capacity = output.count
        let iv = [UInt8](repeating: 32, count: kCCBlockSizeAES128)
        var written = 0
        let status = key.withUnsafeBytes { keyBytes in
            ciphertext.withUnsafeBytes { bytes in
                CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                        keyBytes.baseAddress, key.count, iv, bytes.baseAddress, ciphertext.count, &output, capacity, &written)
            }
        }
        guard status == kCCSuccess else { return nil }
        var plain = Data(output.prefix(written))
        if databaseVersion >= 24 {
            let digest = Data(SHA256.hash(data: Data(domain.utf8)))
            guard plain.starts(with: digest) else { return nil }
            plain.removeFirst(digest.count)
        }
        return String(data: plain, encoding: .utf8)
    }
}
