import Foundation

/// Owner-only, atomic download history with a last-good backup. Clearing it never removes files.
@MainActor
struct DownloadHistoryStore {
    let directory: URL
    private var current: URL { directory.appending(path: "downloads.json") }
    private var backup: URL { directory.appending(path: "downloads.backup.json") }
    static var standard: Self {
        let base = WebProfiles.isTestMode ? SessionStore.testDirectory
            : AppIdentity.dataDirectory
        return Self(directory: base)
    }

    func load() -> [DownloadCenter.Item] { read(current) ?? read(backup) ?? [] }

    func save(_ items: [DownloadCenter.Item]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if let previous = read(current) { try write(JSONEncoder().encode(previous), to: backup) }
        try write(JSONEncoder().encode(items), to: current)
    }

    /// The decrypted file, for checks that inspect what was saved.
    func decrypted(_ name: String) -> Data? {
        (try? Data(contentsOf: directory.appending(path: name))).flatMap { try? SealedStorage.open($0) }
    }

    /// After clearing history, so the last-good copy doesn't keep what was just cleared.
    func discardBackup() { try? FileManager.default.removeItem(at: backup) }

    private func read(_ file: URL) -> [DownloadCenter.Item]? {
        guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 16_000_000,
              let raw = try? Data(contentsOf: file), let data = try? SealedStorage.open(raw), let decoded = try? JSONDecoder().decode([DownloadCenter.Item].self, from: data),
              decoded.count <= 10_000 else { return nil }
        var seen = Set<UUID>()
        return decoded.filter { seen.insert($0.id).inserted }.map { item in
            var item = item
            item.name = String(item.name.prefix(512))
            item.received = max(0, item.received); item.total = max(0, item.total)
            if item.fileURL?.isFileURL == false { item.fileURL = nil }
            return item
        }
    }

    private func write(_ data: Data, to target: URL) throws {
        let pending = directory.appending(path: ".downloads-\(UUID().uuidString).json")
        guard FileManager.default.createFile(atPath: pending.path, contents: try SealedStorage.seal(data), attributes: [.posixPermissions: 0o600]) else { throw CocoaError(.fileWriteUnknown) }
        defer { try? FileManager.default.removeItem(at: pending) }
        let handle = try FileHandle(forWritingTo: pending)
        try handle.synchronize(); try handle.close()
        guard rename(pending.path, target.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
    }
}
