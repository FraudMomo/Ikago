// Prints the public half of an exported Sparkle update key (base64), so a release can check that the key it was given
// matches SUPublicEDKey before signing anything with it. Sparkle exports either the 32-byte seed, or seed and public
// key together (64 bytes); older keys are a 64-byte private key followed by the public key (96 bytes).
import CryptoKit
import Foundation

guard CommandLine.arguments.count == 2,
      let text = try? String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8),
      let data = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
    FileHandle.standardError.write(Data("usage: update_public_key.swift KEYFILE (base64)\n".utf8))
    exit(1)
}
switch data.count {
case 32:
    guard let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: data) else { exit(1) }
    print(key.publicKey.rawRepresentation.base64EncodedString())
case 64, 96:
    print(data.suffix(32).base64EncodedString())
default:
    exit(1)
}
