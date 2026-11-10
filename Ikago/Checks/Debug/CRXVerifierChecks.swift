#if DEBUG
import CryptoKit
import Foundation

/// Store package signatures, with packages built here. Real store packages were checked by hand: they
/// carry an RSA developer proof and the store's ECDSA publisher proof.
@MainActor
enum CRXVerifierChecks {
    static func run(check: (Bool, String) -> Void) {
        let developer = P256.Signing.PrivateKey()
        let key = [UInt8](developer.publicKey.derRepresentation)
        let crxID = Array(SHA256.hash(data: key).prefix(16))
        let id = CRXVerifier.extensionID(crxID)
        let archive = Data([0x50, 0x4B, 0x03, 0x04]) + Data("archive".utf8)

        func field(_ number: Int, _ value: [UInt8]) -> [UInt8] { varint(number << 3 | 2) + varint(value.count) + value }
        func varint(_ value: Int) -> [UInt8] {
            var value = value, out: [UInt8] = []
            repeat { var byte = UInt8(value & 0x7F); value >>= 7; if value > 0 { byte |= 0x80 }; out.append(byte) } while value > 0
            return out
        }
        func package(signedBy signer: P256.Signing.PrivateKey, archive: Data) -> Data {
            let signedHeader = field(1, crxID)
            var message = Data("CRX3 SignedData".utf8) + [0]
            withUnsafeBytes(of: UInt32(signedHeader.count).littleEndian) { message.append(contentsOf: $0) }
            message.append(contentsOf: signedHeader); message.append(archive)
            let signature = [UInt8]((try? signer.signature(for: message).derRepresentation) ?? Data())
            let header = field(3, field(1, key) + field(2, signature)) + field(10000, signedHeader)
            var data = Data("Cr24".utf8)
            withUnsafeBytes(of: UInt32(3).littleEndian) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: UInt32(header.count).littleEndian) { data.append(contentsOf: $0) }
            return data + header + archive
        }
        let good = package(signedBy: developer, archive: archive)
        check((try? CRXVerifier.verifiedArchive(good, id: id, requirePublisher: false)) == archive, "a correctly signed package verifies")
        check((try? CRXVerifier.verifiedArchive(good, id: id)) == nil, "a package without the Web Store's signature is refused")
        check((try? CRXVerifier.verifiedArchive(good, id: String(repeating: "a", count: 32), requirePublisher: false)) == nil,
              "a package for another extension ID is refused")
        var tampered = good; tampered[tampered.count - 1] ^= 1
        check((try? CRXVerifier.verifiedArchive(tampered, id: id, requirePublisher: false)) == nil, "a changed package is refused")
        let forged = package(signedBy: P256.Signing.PrivateKey(), archive: archive)
        check((try? CRXVerifier.verifiedArchive(forged, id: id, requirePublisher: false)) == nil, "a package signed by someone else is refused")
        check((try? CRXVerifier.verifiedArchive(archive, id: id, requirePublisher: false)) == nil, "an unsigned ZIP from the store is refused")
    }
}
#endif
