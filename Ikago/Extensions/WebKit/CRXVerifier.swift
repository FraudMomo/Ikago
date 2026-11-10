import CryptoKit
import Foundation
import Security

/// Checks a Chrome Web Store package the way Chrome does (components/crx_file/crx_verifier.cc) before
/// anything is unpacked: a CRX3 file whose every signature verifies over its contents, signed by the
/// key its extension ID comes from and by the Web Store's own publisher key. So neither a network
/// attacker nor a compromised download can hand Ikago a package the store didn't publish.
enum CRXVerifier {
    struct Failure: LocalizedError {
        let reason: String
        var errorDescription: String? { "The extension’s signature couldn’t be verified (\(reason)), so it wasn’t installed." }
    }

    /// SHA-256 of the Web Store's "ecdsa_2017_public" publisher key, from Chromium's crx_verifier.cc.
    static let publisherKeyHash: [UInt8] = [
        0x61, 0xf7, 0xf2, 0xa6, 0xbf, 0xcf, 0x74, 0xcd, 0x0b, 0xc1, 0xfe, 0x24, 0x97, 0xcc, 0x9b, 0x04,
        0x25, 0x4c, 0x65, 0x8f, 0x79, 0xf2, 0x14, 0x53, 0x92, 0x86, 0x7e, 0xa8, 0x36, 0x63, 0x67, 0xcf]
    private static let context = Data("CRX3 SignedData".utf8) + [0]

    /// Returns the ZIP archive inside a verified package for extension `id`.
    static func verifiedArchive(_ data: Data, id expectedID: String, requirePublisher: Bool = true) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count > 12, bytes.starts(with: Array("Cr24".utf8)) else { throw Failure(reason: "not a CRX file") }
        guard u32(bytes, 4) == 3 else { throw Failure(reason: "not the CRX3 format the store publishes") }
        let headerSize = u32(bytes, 8)
        guard headerSize < bytes.count - 12 else { throw Failure(reason: "damaged header") }
        let header = Array(bytes[12..<(12 + headerSize)])
        // A ZIP end-of-directory token in the header could make unzipping read the wrong archive.
        for token: [UInt8] in [[0x50, 0x4B, 0x05, 0x06], [0x50, 0x4B, 0x06, 0x07], [0x50, 0x4B, 0x06, 0x06]]
        where header.firstRange(of: token) != nil {
            throw Failure(reason: "unsafe header")
        }
        var rsa: [[UInt8]] = [], ecdsa: [[UInt8]] = [], signedHeader: [UInt8]?
        for (field, value) in try fields(header) {
            switch field {
            case 2: rsa.append(value)
            case 3: ecdsa.append(value)
            case 10000: signedHeader = value
            default: break
            }
        }
        guard let signedHeader, let crxID = try fields(signedHeader).first(where: { $0.0 == 1 })?.1, crxID.count == 16
        else { throw Failure(reason: "missing extension ID") }
        let declaredID = extensionID(crxID)
        guard declaredID == expectedID else { throw Failure(reason: "it’s for a different extension") }

        let archive = data.subdata(in: (12 + headerSize)..<data.count)
        var message = context
        withUnsafeBytes(of: UInt32(signedHeader.count).littleEndian) { message.append(contentsOf: $0) }
        message.append(contentsOf: signedHeader)
        message.append(archive)

        var developer = false, publisher = false
        for (proofs, isRSA) in [(rsa, true), (ecdsa, false)] {
            for proof in proofs {
                let parts = try fields(proof)
                guard let key = parts.first(where: { $0.0 == 1 })?.1, let signature = parts.first(where: { $0.0 == 2 })?.1
                else { throw Failure(reason: "incomplete proof") }
                let hash = Array(SHA256.hash(data: key))
                if extensionID(Array(hash.prefix(16))) == declaredID { developer = true }
                if hash == publisherKeyHash { publisher = true }
                guard isRSA ? verifyRSA(key: key, signature: signature, message: message)
                            : verifyECDSA(key: key, signature: signature, message: message)
                else { throw Failure(reason: "a signature doesn’t match the contents") }
            }
        }
        guard developer else { throw Failure(reason: "not signed by the extension’s own key") }
        guard publisher || !requirePublisher else { throw Failure(reason: "not signed by the Chrome Web Store") }
        return archive
    }

    /// Chrome's ID alphabet: each hex digit of the first 16 bytes becomes a letter a–p.
    static func extensionID(_ bytes: [UInt8]) -> String {
        let letters = Array("abcdefghijklmnop")
        return String(bytes.flatMap { [letters[Int($0 >> 4)], letters[Int($0 & 0xF)]] })
    }

    private static func u32(_ bytes: [UInt8], _ offset: Int) -> Int {
        Int(bytes[offset]) | Int(bytes[offset + 1]) << 8 | Int(bytes[offset + 2]) << 16 | Int(bytes[offset + 3]) << 24
    }

    /// The length-delimited fields of a protocol buffer message; other wire types are skipped.
    private static func fields(_ bytes: [UInt8]) throws -> [(Int, [UInt8])] {
        var index = 0, result: [(Int, [UInt8])] = []
        func varint() throws -> Int {
            var value = 0, shift = 0
            while true {
                guard index < bytes.count, shift < 63 else { throw Failure(reason: "damaged header") }
                let byte = bytes[index]; index += 1
                value |= Int(byte & 0x7F) << shift
                if byte < 0x80 { return value }
                shift += 7
            }
        }
        while index < bytes.count {
            let key = try varint()
            switch key & 7 {
            case 0: _ = try varint()
            case 1: index += 8
            case 5: index += 4
            case 2:
                let length = try varint()
                guard length >= 0, length <= bytes.count - index else { throw Failure(reason: "damaged header") }
                result.append((key >> 3, Array(bytes[index..<(index + length)])))
                index += length
            default: throw Failure(reason: "damaged header")
            }
            guard index <= bytes.count else { throw Failure(reason: "damaged header") }
        }
        return result
    }

    private static func verifyECDSA(key: [UInt8], signature: [UInt8], message: Data) -> Bool {
        guard let key = try? P256.Signing.PublicKey(derRepresentation: key),
              let signature = try? P256.Signing.ECDSASignature(derRepresentation: signature) else { return false }
        return key.isValidSignature(signature, for: message)
    }

    private static func verifyRSA(key: [UInt8], signature: [UInt8], message: Data) -> Bool {
        guard let pkcs1 = subjectPublicKey(key) else { return false }
        let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPublic]
        guard let secKey = SecKeyCreateWithData(Data(pkcs1) as CFData, attributes as CFDictionary, nil) else { return false }
        return SecKeyVerifySignature(secKey, .rsaSignatureMessagePKCS1v15SHA256, message as CFData, Data(signature) as CFData, nil)
    }

    /// The key inside a DER SubjectPublicKeyInfo: SEQUENCE { AlgorithmIdentifier, BIT STRING }.
    private static func subjectPublicKey(_ der: [UInt8]) -> [UInt8]? {
        var index = 0
        func header(_ tag: UInt8) -> Int? {
            guard index + 2 <= der.count, der[index] == tag else { return nil }
            index += 1
            var length = Int(der[index]); index += 1
            if length & 0x80 != 0 {
                let count = length & 0x7F
                guard count <= 4, index + count <= der.count else { return nil }
                length = der[index..<(index + count)].reduce(0) { $0 << 8 | Int($1) }
                index += count
            }
            return index + length <= der.count ? length : nil
        }
        // Strict like Chrome: the outer length must cover exactly the whole key.
        guard let outer = header(0x30), index + outer == der.count, let algorithm = header(0x30) else { return nil }
        index += algorithm
        guard let bits = header(0x03), bits > 1, der[index] == 0 else { return nil }
        return Array(der[(index + 1)..<(index + bits)])
    }
}
