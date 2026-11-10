import Foundation

/// Keeps Chrome Web Store extensions the same on WebKit and Chromium. Both engines record what you
/// add, turn on or off, and remove here; the running engine catches up at launch, because only one
/// engine runs at a time. Each change wins over older ones. Only Web Store extensions sync: they have
/// the same ID on both engines. Local folders and Safari extensions stay with the engine they're on.
/// An extension one engine can't run is remembered and not retried until it updates.
/// Extensions' own settings and data don't move between engines.
@MainActor
enum ExtensionSync {
    enum Engine: String, Codable, Sendable { case webkit, chromium }

    struct Entry: Codable, Equatable, Sendable {
        var id: String
        var enabled = true
        var removed = false
        /// When the person last changed it, on either engine.
        var changed: Double
        /// Engines that couldn't install it, with the reason shown in Settings.
        var unsupported: [String: String]? = nil
    }

    static var file: URL {
        let base = WebProfiles.isTestMode ? SessionStore.testDirectory : AppIdentity.dataDirectory
        return base.appending(path: "Extensions/sync.json")
    }

    static func entries() -> [Entry] {
        guard let data = try? Data(contentsOf: file), let plain = try? SealedStorage.open(data) else { return [] }
        return ((try? JSONDecoder().decode([Entry].self, from: plain)) ?? []).filter { WebStoreInstaller.isValidID($0.id) }
    }

    private static func save(_ entries: [Entry]) {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try SealedStorage.seal(JSONEncoder().encode(entries)).write(to: file, options: .atomic)
        } catch {
            NSLog("Ikago: extension sync not saved: %@", error.localizedDescription)
        }
    }

    private static func update(_ id: String, _ change: (inout Entry) -> Void) {
        guard WebStoreInstaller.isValidID(id) else { return }
        var all = entries()
        var entry = all.first { $0.id == id } ?? Entry(id: id, changed: 0)
        change(&entry)
        all.removeAll { $0.id == id }
        all.append(entry)
        save(all)
    }

    // MARK: What the person did (either engine)

    static func added(_ id: String) {
        update(id) { $0.enabled = true; $0.removed = false; $0.unsupported = nil; $0.changed = Date().timeIntervalSince1970 }
    }

    static func setEnabled(_ id: String, _ enabled: Bool) {
        update(id) { $0.enabled = enabled; $0.removed = false; $0.changed = Date().timeIntervalSince1970 }
    }

    static func removed(_ id: String) {
        update(id) { $0.removed = true; $0.changed = Date().timeIntervalSince1970 }
    }

    /// The engine tried and failed; it won't try again until the person adds it once more.
    static func unsupported(_ id: String, on engine: Engine, reason: String) {
        update(id) { entry in
            var reasons = entry.unsupported ?? [:]
            reasons[engine.rawValue] = reason
            entry.unsupported = reasons
        }
    }

    // MARK: Catching up

    struct Plan: Equatable {
        var install: [String] = [], remove: [String] = [], enable: [String] = [], disable: [String] = []
        var isEmpty: Bool { install.isEmpty && remove.isEmpty && enable.isEmpty && disable.isEmpty }
    }

    /// What `engine` must do to match the ledger, given its Web Store extensions and whether each is on.
    static func plan(for engine: Engine, installed: [String: Bool], entries: [Entry]) -> Plan {
        var plan = Plan()
        for entry in entries {
            let current = installed[entry.id]
            if entry.removed {
                if current != nil { plan.remove.append(entry.id) }
            } else if let current {
                if current != entry.enabled {
                    if entry.enabled { plan.enable.append(entry.id) } else { plan.disable.append(entry.id) }
                }
            } else if entry.unsupported?[engine.rawValue] == nil {
                plan.install.append(entry.id)
            }
        }
        return plan
    }

    /// Extensions every new Ikago starts with: uBlock Origin Lite, the content blocker that runs on both
    /// engines (classic uBlock Origin is Manifest V2, which current Chromium no longer runs).
    static let defaults = ["ddkjiahejlhfcafbddmgiahcphecmpfh"]
    private static let seededKey = "ExtensionDefaultsSeeded"

    /// Adds the defaults once. Removing one later is respected: it is never added back.
    static func seedDefaults(testing: Bool = false) {
        guard testing || (!WebProfiles.isTestMode && !UserDefaults.standard.bool(forKey: seededKey)) else { return }
        let known = Set(entries().map(\.id))
        for id in defaults where !known.contains(id) {
            update(id) { $0.enabled = true; $0.changed = 1 }
        }
        if !testing { UserDefaults.standard.set(true, forKey: seededKey) }
    }

    /// Records Web Store extensions an engine had before syncing existed, so the other engine gets them too.
    static func adopt(_ installed: [String: Bool]) {
        let known = Set(entries().map(\.id))
        for (id, enabled) in installed where !known.contains(id) {
            update(id) { $0.enabled = enabled; $0.changed = 1 }  // older than anything the person does from now on
        }
    }
}
