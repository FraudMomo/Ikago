import Foundation
import os

/// On-disk session. The original fields are required; every field added since is optional,
/// so sessions written by older builds still restore.
struct Session: Codable, Equatable {
    var tabs: [SavedTab] = []
    var active: String?
    var closed: [SavedTab] = []
    var history: [Visit] = []
    var theme: String = "mist"  // legacy field, kept so older builds can read the file
    var search: String = SearchEngine.duckduckgo.rawValue
    var sidebar: Bool = true
    // Later additions.
    var split: [String]? = nil  // legacy single split; read only
    var splits: [[String]]? = nil
    var splitVertical: Bool? = nil  // legacy; read only
    var splitLayout: String? = nil
    var spaces: [SpaceProfile]? = nil
    var activeSpace: UUID? = nil
    var lastActiveTab: [String: String]? = nil  // Space UUID → tab ID
    var folders: [TabFolder]? = nil
    var layout: String? = nil
    var colorMode: String? = nil
    var sidebarWidth: Double? = nil
    var newTab: NewTabSettings? = nil
    var ui: UISettings? = nil
    var chrome: ChromeLayout? = nil
    var browser: BrowserPreferences? = nil
    var bookmarks: [Bookmark]? = nil
    var bookmarkFolders: [BookmarkFolder]? = nil

    static let maxTabs = 100, maxClosed = 20, maxHistory = 1000

    /// Rejects sessions that exceed the limits or repeat tab IDs.
    func validate() throws {
        struct Invalid: Error {}
        guard tabs.count <= Self.maxTabs, closed.count <= Self.maxClosed,
              history.count <= Self.maxHistory else { throw Invalid() }
        guard Set(tabs.map(\.id)).count == tabs.count else { throw Invalid() }
        for tab in tabs + closed {
            guard Self.isValidID(tab.id), AddressResolver.isPageURL(tab.url) || InternalPage(url: tab.url) != nil || ExtensionURL.isExtension(tab.url),
                  tab.title.utf8.count <= 2048
            else { throw Invalid() }
        }
        for visit in history where !AddressResolver.isWebURL(visit.url) || visit.title.utf8.count > 2048 {
            throw Invalid()
        }
        guard (bookmarks ?? []).count <= 5000, Set((bookmarks ?? []).map(\.id)).count == (bookmarks ?? []).count else { throw Invalid() }
        for bookmark in bookmarks ?? [] {
            guard Self.isValidID(bookmark.id), AddressResolver.isWebURL(bookmark.url),
                  bookmark.title.utf8.count <= 2048 else { throw Invalid() }
        }
        try BookmarkFolder.validate(bookmarkFolders ?? [], bookmarks: bookmarks ?? [])
        guard SearchEngine(rawValue: search) != nil else { throw Invalid() }
        if let active, !tabs.contains(where: { $0.id == active }) { throw Invalid() }
        guard (spaces ?? []).count <= 50, (folders ?? []).count <= 500 else { throw Invalid() }
        for folder in folders ?? [] where !Self.isValidID(folder.id) || folder.name.utf8.count > 256 { throw Invalid() }
    }

    static func isValidID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 64 && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }
}

struct UISettings: Codable, Equatable {
    var glass: Bool
    var inset: Double
    var history: Bool
    var devTools: Bool
    var gap: Double? = nil
    var address: String? = nil
    var tintBar: Bool? = nil
    var barHeight: Double? = nil
    var barBorder: Double? = nil
    var barGap: Double? = nil
    var barRounded: Bool? = nil
}

struct NewTabSettings: Codable, Equatable {
    var mode: String
    var homepage: String
    var extensionID: String?
    var focusAddressBar: Bool? = nil
}

/// Atomic JSON persistence with last-good backup recovery:
/// write `session.pending.json` (0600, fsync) → copy the valid current file to
/// `session.backup.json` → rename pending over `session.json` → fsync the directory.
struct SessionStore {
    let directory: URL
    /// Saves run here in order, off the main thread; `saveAndWait` runs after every queued one.
    private let writer = SessionWriter()

    init(directory: URL) { self.directory = directory }
    private var current: URL { directory.appending(path: "session.json") }
    private var backup: URL { directory.appending(path: "session.backup.json") }
    private var pending: URL { directory.appending(path: "session.pending.json") }

    static var testDirectory: URL {
        #if DEBUG
        if let path = DebugEnvironment.value("IKAGO_TEST_PROFILE") {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        #endif
        return FileManager.default.temporaryDirectory.appending(path: "IkagoTestProfile")
    }

    static var standard: SessionStore {
        if CommandLine.arguments.contains("--cef-smoke"), let path = ProcessInfo.processInfo.environment["IKAGO_CEF_FIXTURE_PROFILE"] {
            return SessionStore(directory: URL(fileURLWithPath: path, isDirectory: true))
        }
        #if DEBUG
        // Unattended test mode (see TestDriver): never touch the real session.
        if DebugEnvironment.value("IKAGO_TEST_MODE") != nil {
            return SessionStore(directory: testDirectory)
        }
        #endif
        return SessionStore(directory: AppIdentity.dataDirectory)
    }

    enum LoadResult {
        case loaded(Session)
        case fresh
        case unreadable(String)  // both files corrupt: moved aside under this suffix, app starts empty
    }

    func load() -> LoadResult {
        guard FileManager.default.fileExists(atPath: current.path) else { return .fresh }
        let session = read(current)
        writer.currentIsValid.withLock { $0 = session != nil }
        if let session = session ?? read(backup) { return .loaded(session) }
        // Keep the unreadable files for recovery; the next save must not overwrite them.
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        for file in [current, backup] where FileManager.default.fileExists(atPath: file.path) {
            let aside = directory.appending(path: file.deletingPathExtension().lastPathComponent + ".unreadable-\(stamp).json")
            try? FileManager.default.moveItem(at: file, to: aside)
        }
        return .unreadable(stamp)
    }

    func save(_ session: Session) throws {
        try session.validate()
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        let data = try SealedStorage.seal(JSONEncoder().encode(session))

        let fd = open(pending.path, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        guard fd >= 0 else { throw CocoaError(.fileWriteUnknown) }
        let written = data.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        let synced = fsync(fd) == 0
        close(fd)
        guard written == data.count, synced else { throw CocoaError(.fileWriteUnknown) }

        // Only a valid session becomes the backup. Known from this process's last load or save; read only when unknown.
        let currentIsValid = writer.currentIsValid.withLock { $0 } ?? (read(current) != nil)
        if currentIsValid, fm.fileExists(atPath: current.path) {
            _ = try? fm.removeItem(at: backup)
            // A session from before encryption must not linger in plain text as the backup.
            if Self.isSealedFile(current) { try fm.copyItem(at: current, to: backup) }
            else { try writeOwnerOnly(SealedStorage.seal(Data(contentsOf: current)), to: backup) }
        }
        guard rename(pending.path, current.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
        writer.currentIsValid.withLock { $0 = true }
        let dirFD = open(directory.path, O_RDONLY)
        if dirFD >= 0 { fsync(dirFD); close(dirFD) }
    }

    /// Queues a save off the main thread, in order with the others. `failed` runs on the main actor if it isn't saved.
    func saveInBackground(_ session: Session, failed: @escaping @MainActor @Sendable () -> Void) {
        let box = SessionBox(session: session)
        writer.queue.async {
            if !saveLogged(box.session) { Task { @MainActor in failed() } }
        }
    }

    /// Saves now, after any queued saves (quitting, closing a window, relaunching).
    @discardableResult
    func saveAndWait(_ session: Session) -> Bool {
        let box = SessionBox(session: session)
        return writer.queue.sync { saveLogged(box.session) }
    }

    private func saveLogged(_ session: Session) -> Bool {
        do {
            try save(session)
            // History got shorter: something was deleted, so the copy of the old session must go too.
            let count = session.history.count
            if let saved = writer.savedHistoryCount.withLock({ $0 }), count < saved { discardBackup() }
            writer.savedHistoryCount.withLock { $0 = count }
            return true
        } catch {
            NSLog("Ikago: session not saved: \(error)")
            return false
        }
    }

    private static func isSealedFile(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        return SealedStorage.isSealed((try? handle.read(upToCount: 8)) ?? Data())
    }

    /// After clearing data: each save copies the previous session aside, which would otherwise keep
    /// what was just cleared on disk. `session.json` is valid by now, so nothing depends on the backup.
    func discardBackup() {
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.removeItem(at: pending)
    }

    private func writeOwnerOnly(_ data: Data, to url: URL) throws {
        let fd = open(url.path, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        guard fd >= 0 else { throw CocoaError(.fileWriteUnknown) }
        let written = data.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        let synced = fsync(fd) == 0
        close(fd)
        guard written == data.count, synced else { throw CocoaError(.fileWriteUnknown) }
    }

    /// The decrypted session file, for checks and diagnostics that inspect what was saved.
    func decrypted(_ name: String) -> Data? {
        (try? Data(contentsOf: directory.appending(path: name))).flatMap { try? SealedStorage.open($0) }
    }

    private func read(_ url: URL) -> Session? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 8_000_000,
              let raw = try? Data(contentsOf: url), let data = try? SealedStorage.open(raw),
              let session = try? JSONDecoder().decode(Session.self, from: data),
              (try? session.validate()) != nil
        else { return nil }
        return session
    }
}

/// One store's save queue and what it knows about the files, shared by copies of the store.
private final class SessionWriter: Sendable {
    let queue = DispatchQueue(label: "app.ikago.session.save", qos: .utility)
    /// Whether session.json holds a valid session (nil: unknown, so a save reads it first).
    let currentIsValid = OSAllocatedUnfairLock<Bool?>(initialState: nil)
    /// History length at the last successful save, so a deletion also discards the backup.
    let savedHistoryCount = OSAllocatedUnfairLock<Int?>(initialState: nil)
}

/// A session is plain values; it crosses to the save queue as a copy.
private struct SessionBox: @unchecked Sendable { let session: Session }
