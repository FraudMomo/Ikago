#if DEBUG
import Foundation

/// Encryption at rest: round trips, damage, and files from before it existed.
@MainActor
enum SealedChecks {
    static func run(check: (Bool, String) -> Void) async {
        let secret = Data("https://private.example/?q=secret".utf8)
        guard let sealed = try? SealedStorage.seal(secret) else { return check(false, "sealing works") }
        check(SealedStorage.isSealed(sealed) && sealed.range(of: Data("private.example".utf8)) == nil, "sealed data hides its contents")
        check((try? SealedStorage.open(sealed)) == secret, "sealed data opens again")
        check((try? SealedStorage.open(secret)) == secret, "files from before encryption still open")
        var damaged = sealed; damaged[damaged.count - 1] ^= 0xFF
        check((try? SealedStorage.open(damaged)) == nil, "damaged or tampered data is rejected")

        // A plain session from before encryption upgrades, and leaves no plain copy behind.
        let directory = FileManager.default.temporaryDirectory.appending(path: "ikago-sealed-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = SessionStore(directory: directory)
        var session = Session()
        session.history = [Visit(url: "https://private.example/plain-probe", title: "probe", time: 1)]
        try? JSONEncoder().encode(session).write(to: directory.appending(path: "session.json"))
        guard case .loaded(let restored) = store.load(), restored.history.count == 1 else { return check(false, "a plain session loads") }
        try? store.save(restored)
        for name in ["session.json", "session.backup.json"] {
            let raw = (try? Data(contentsOf: directory.appending(path: name))) ?? Data()
            check(SealedStorage.isSealed(raw) && raw.range(of: Data("plain-probe".utf8)) == nil, "upgrading leaves \(name) encrypted")
        }
        guard case .loaded(let again) = store.load() else { return check(false, "an encrypted session loads") }
        check(again.history.first?.url.contains("plain-probe") == true, "an encrypted session restores its history")
    }
}
#endif
