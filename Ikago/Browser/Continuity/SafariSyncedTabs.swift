import Foundation
import Observation

/// Tabs open in Safari on the person's other devices, and their Safari Tab Groups, read from the copies Safari on this
/// Mac keeps of what iCloud syncs. Read only, through read-only SQLite handles; nothing is written back.
/// - `CloudTabs.db`: one row per device (`cloud_tab_devices`) and per open tab (`cloud_tabs`); a tab's order is the
///   first `sortValue` in its zlib-compressed JSON `position`.
/// - `SafariTabs.db`: tab groups are folders (`bookmarks`, type 1, subtype 0) under the root or under a profile
///   folder (subtype 2); their tabs are type 0 rows. Each group's pinned-tab list (subtype 1) is left out.
/// The formats are Safari's own and undocumented, so anything unexpected reads as "nothing to show".
struct SafariSyncedTabs: Sendable {
    struct Tab: Sendable, Identifiable, Hashable {
        let id: String
        let title: String
        let url: String
    }

    struct Device: Sendable, Identifiable {
        enum Kind: Sendable { case phone, pad, mac, other }
        let id: String
        let name: String
        let kind: Kind
        let updated: Date
        let tabs: [Tab]
        var symbol: String {
            switch kind { case .phone: "iphone"; case .pad: "ipad"; case .mac: "laptopcomputer"; case .other: "desktopcomputer" }
        }
    }

    struct Group: Sendable, Identifiable {
        let id: String
        let name: String
        let profile: String?
        let updated: Date?
        let tabs: [Tab]
    }

    var devices: [Device] = []
    var groups: [Group] = []
    /// When Safari last wrote either copy: the freshest anything shown can be.
    var updated: Date?

    static var folder: URL {
        #if DEBUG
        if let fixture = ProcessInfo.processInfo.environment["IKAGO_SAFARI_FOLDER"] { return URL(fileURLWithPath: fixture) }
        #endif
        return FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Containers/com.apple.Safari/Data/Library/Safari")
    }
    /// Safari stores dates as seconds since 2001.
    private static func date(_ value: Any?) -> Date? {
        (value as? Double).map { Date(timeIntervalSinceReferenceDate: $0) } ?? (value as? Int64).map { Date(timeIntervalSinceReferenceDate: Double($0)) }
    }

    /// Throws only when macOS refused access; a missing or unreadable format reads as empty.
    static func read(folder: URL = SafariSyncedTabs.folder) throws -> SafariSyncedTabs {
        var result = SafariSyncedTabs()
        let cloud = folder.appending(path: "CloudTabs.db"), tabs = folder.appending(path: "SafariTabs.db")
        result.updated = [cloud, tabs].compactMap { modified($0) }.max()
        do { result.devices = try devices(ImportDatabase(cloud)) } catch where ImportAccessError.isPermissionDenied(error) { throw error } catch {}
        do { result.groups = try groups(ImportDatabase(tabs)) } catch where ImportAccessError.isPermissionDenied(error) { throw error } catch {}
        return result
    }

    static func lastWrite(folder: URL = SafariSyncedTabs.folder) -> Date? {
        ["CloudTabs.db", "SafariTabs.db"].compactMap { modified(folder.appending(path: $0)) }.max()
    }

    private static func modified(_ file: URL) -> Date? {
        // Safari writes through a WAL, so the newest of the database and its log is the last write.
        [file, URL(fileURLWithPath: file.path + "-wal")].compactMap {
            try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }.max()
    }

    private static func devices(_ database: ImportDatabase) throws -> [Device] {
        let tabRows = try database.rows("SELECT tab_uuid, device_uuid, position, title, url FROM cloud_tabs")
        var byDevice: [String: [(Double, Tab)]] = [:]
        for row in tabRows {
            guard let device = row["device_uuid"] as? String, let url = row["url"] as? String, AddressResolver.isWebURL(url) else { continue }
            let tab = Tab(id: row["tab_uuid"] as? String ?? UUID().uuidString, title: (row["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? url, url: url)
            byDevice[device, default: []].append((sortValue(row["position"] as? Data), tab))
        }
        return try database.rows("SELECT device_uuid, device_name, device_type_identifier, last_modified FROM cloud_tab_devices").compactMap { row in
            guard let id = row["device_uuid"] as? String else { return nil }
            let type = (row["device_type_identifier"] as? String ?? "").lowercased()
            let kind: Device.Kind = type.contains("iphone") ? .phone : type.contains("ipad") ? .pad : type.contains("mac") ? .mac : .other
            let tabs = (byDevice[id] ?? []).sorted { $0.0 < $1.0 }.map(\.1)
            return Device(id: id, name: row["device_name"] as? String ?? "Device", kind: kind,
                          updated: date(row["last_modified"]) ?? .distantPast, tabs: tabs)
        }
        .sorted { ($0.kind == .phone ? 0 : 1, $1.updated) < ($1.kind == .phone ? 0 : 1, $0.updated) }
    }

    private static func sortValue(_ blob: Data?) -> Double {
        guard let blob, let json = blob.zlibInflated, let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let first = (object["sortValues"] as? [[String: Any]])?.first, let value = first["sortValue"] as? NSNumber else { return .greatestFiniteMagnitude }
        return value.doubleValue
    }

    static func groups(_ database: ImportDatabase) throws -> [Group] {
        let folders = try database.rows("""
            SELECT id, parent, subtype, title FROM bookmarks WHERE type = 1 AND deleted = 0 AND parent IS NOT NULL ORDER BY order_index
            """)
        let profiles = Dictionary(folders.filter { ($0["subtype"] as? Int64) == 2 }.compactMap { row -> (Int64, String)? in
            guard let id = row["id"] as? Int64 else { return nil }
            return (id, row["title"] as? String ?? "")
        }, uniquingKeysWith: { first, _ in first })
        let groupRows = folders.filter { row in
            guard (row["subtype"] as? Int64) == 0, let parent = row["parent"] as? Int64 else { return false }
            return parent == 0 || profiles[parent] != nil
        }
        let ids = groupRows.compactMap { $0["id"] as? Int64 }
        guard !ids.isEmpty else { return [] }
        let tabRows = try database.rows("""
            SELECT id, parent, title, url, last_modified FROM bookmarks
            WHERE type = 0 AND deleted = 0 AND parent IN (\(ids.map(String.init).joined(separator: ","))) ORDER BY parent, order_index
            """)
        var tabs: [Int64: [Tab]] = [:], updated: [Int64: Date] = [:]
        for row in tabRows {
            guard let parent = row["parent"] as? Int64, let url = row["url"] as? String, AddressResolver.isWebURL(url) else { continue }
            let id = row["id"] as? Int64 ?? 0
            tabs[parent, default: []].append(Tab(id: "safari-tab-\(id)", title: (row["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? url, url: url))
            if let date = date(row["last_modified"]) { updated[parent] = max(updated[parent] ?? date, date) }
        }
        return groupRows.compactMap { row in
            guard let id = row["id"] as? Int64, let list = tabs[id], !list.isEmpty else { return nil }
            let profile = (row["parent"] as? Int64).flatMap { profiles[$0] }.flatMap { $0.isEmpty ? nil : $0 }
            return Group(id: "safari-group-\(id)", name: row["title"] as? String ?? "Tab Group", profile: profile, updated: updated[id], tabs: list)
        }
    }
}

private extension Data {
    /// zlib (RFC 1950) to plain bytes: Foundation's `.zlib` is raw deflate, so the 2-byte header goes first.
    var zlibInflated: Data? {
        guard count > 6 else { return nil }
        return try? (dropFirst(2) as NSData).decompressed(using: .zlib) as Data
    }
}

/// Reads Safari's copies when asked and keeps the last good result for the Devices list.
@MainActor @Observable
final class SafariSyncedTabsModel {
    static let shared = SafariSyncedTabsModel()
    private(set) var tabs = SafariSyncedTabs()
    private(set) var denied = false
    private(set) var loaded = false
    @ObservationIgnored private var reading = false
    @ObservationIgnored private var lastWrite: Date?

    /// Re-reads only when Safari wrote since the last read (or `force`): macOS syncs these in the background, even
    /// with Safari closed, so watching the files is enough to stay current.
    func refresh(force: Bool = false) async {
        guard !reading else { return }
        let write = await Task.detached { SafariSyncedTabs.lastWrite() }.value
        if !force, loaded, !denied, write == lastWrite { return }
        lastWrite = write
        reading = true
        defer { reading = false }
        do {
            tabs = try await Task.detached { try SafariSyncedTabs.read() }.value
            denied = false
        } catch {
            denied = true
        }
        loaded = true
    }
}
