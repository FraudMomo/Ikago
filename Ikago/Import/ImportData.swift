import Foundation
import IKCEFBridge
import WebKit

struct ImportTab: Sendable {
    var url: String
    var title: String
    var pinned = false
    var group: String?
    var groupID: String?
    var groupColor: String?
    var groupCollapsed = false
}

/// A bookmark and the folders it sits in, outermost first ("Bookmarks Bar", "Work").
struct ImportedBookmark: Sendable {
    var url: String
    var title: String
    var folders: [String] = []
}

struct ImportedCookie: Sendable {
    var domain: String
    var path = "/"
    var name: String
    var value: String
    var secure = false
    var httpOnly = false
    var expires: Date?
    /// Chromium and Firefox both store 1 = Lax, 2 = Strict (0/-1: none or unspecified).
    var sameSite: Int64 = -1

    var cookie: HTTPCookie? {
        guard !domain.isEmpty, !name.isEmpty, !domain.contains(where: { $0.isWhitespace || $0 == "/" }),
              expires.map({ $0 > Date() }) ?? true else { return nil }
        var properties: [HTTPCookiePropertyKey: Any] = [.domain: domain, .path: path, .name: name, .value: value]
        if secure { properties[.secure] = "TRUE" }
        if httpOnly { properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
        if let expires { properties[.expires] = expires }
        if sameSite == 1 { properties[.sameSitePolicy] = HTTPCookieStringPolicy.sameSiteLax.rawValue }
        if sameSite == 2 { properties[.sameSitePolicy] = HTTPCookieStringPolicy.sameSiteStrict.rawValue }
        return HTTPCookie(properties: properties)
    }
}

struct BrowserImportData: Sendable {
    var bookmarks: [ImportedBookmark] = []
    var history: [Visit] = []
    var tabs: [ImportTab] = []
    var cookies: [ImportedCookie] = []
    /// From a passwords file (CSV, alone or in an export archive); `passwordsSkipped` rows had no website or password.
    var passwords: [PasswordVault.NewLogin] = []
    var passwordsSkipped = 0
    var notes: [String] = []
    var accessIssues: [String] = []
    /// Some data is in a place only Full Disk Access opens (Safari's container: its cookies and open tabs).
    var needsFullDiskAccess = false
    /// The browser it came from, for the "Imported from …" bookmark folder.
    var sourceName = ""
    /// Ikago's own export: its bookmarks go back where they were (the Bookmarks Bar and its folders), not into an
    /// "Imported" folder, so moving to another Mac or restoring a backup keeps the layout.
    var fromIkago = false
    var hasData: Bool { !bookmarks.isEmpty || !history.isEmpty || !tabs.isEmpty || !cookies.isEmpty || !passwords.isEmpty }

    /// Adds another part of the same export (an archive's files).
    mutating func merge(_ other: BrowserImportData) {
        bookmarks += other.bookmarks; history += other.history; tabs += other.tabs; cookies += other.cookies
        passwords += other.passwords; passwordsSkipped += other.passwordsSkipped
        notes += other.notes; accessIssues += other.accessIssues
        needsFullDiskAccess = needsFullDiskAccess || other.needsFullDiskAccess
        fromIkago = fromIkago || other.fromIkago
    }
}

struct ImportSelection: Sendable {
    var bookmarks = true
    var history = true
    var tabs = true
    var cookies = false
    var passwords = true
}

/// What an import did, one line per kind of data: how much was found, how much came in, and why the rest didn't.
struct ImportReport: Equatable, Sendable {
    struct Item: Equatable, Sendable, Identifiable {
        var kind: String
        /// How the summary names them ("history pages").
        var noun: String
        var symbol: String
        var found: Int
        var imported: Int
        /// Details, each with its count: why some weren't imported ("3 already in Ikago"), or where they went.
        var details: [String] = []
        var id: String { kind }

        var summary: String {
            let lead = imported == found ? "\(imported) imported" : "\(imported) of \(found) imported"
            return ([lead] + details).joined(separator: " · ")
        }
    }

    var items: [Item] = []
    /// Something stopped the import before anything was merged.
    var failure: String?

    /// One sentence for places that show a single line (and older callers).
    var summary: String {
        if let failure { return failure }
        let parts = items.filter { $0.imported > 0 }.map { item in
            "\(item.imported) \(item.noun)" + (item.details.first { $0.hasPrefix("in ") }.map { " " + $0 } ?? "")
        }
        let limited = items.contains { $0.details.contains { $0.contains("limit") } }
        return (parts.isEmpty ? "Nothing new to import." : "Imported " + parts.joined(separator: ", ") + ".")
            + (limited ? " Some items were skipped because Ikago’s limit was reached." : "")
            + " Duplicates were skipped; existing data was kept."
    }
}

extension BrowserState {
    /// Merge only the selected data. Imported identities never overwrite an existing tab or Space.
    func applyImport(_ data: BrowserImportData, selection: ImportSelection, to spaceID: UUID,
                     passwordVault: PasswordVault? = nil) async -> ImportReport {
        guard !isFrozen else { return ImportReport(failure: "Import stopped because Ikago is closing.") }
        guard let destination = spaces.first(where: { $0.id == spaceID }) else {
            return ImportReport(failure: "The destination Space was removed. Choose another Space.")
        }
        var report = ImportReport()
        func plural(_ count: Int, _ text: String) -> String? { count > 0 ? "\(count) \(text)" : nil }

        if selection.bookmarks, !data.bookmarks.isEmpty {
            // Like Chrome: everything goes into one "Imported from …" folder with the source's own folders inside it.
            // Importing again reuses those folders and skips bookmarks already in the same folder.
            let root = data.fromIkago ? nil
                : importFolder(named: data.sourceName.isEmpty ? "Imported" : "Imported from \(data.sourceName)", parent: nil)
            // Importing again is safe: a bookmark already in some folder is kept where it is, and one left at the top
            // level (earlier imports brought everything in flat) moves into its folder instead of being copied.
            let known = Set(bookmarkFolders.map(\.id))
            var placed = Set(bookmarks.filter { $0.folderID.map(known.contains) ?? false }.map(\.url))
            var loose: [String: Int] = [:]
            for (index, bookmark) in bookmarks.enumerated() where !(bookmark.folderID.map(known.contains) ?? false) {
                loose[bookmark.url] = loose[bookmark.url] ?? index
            }
            var added = 0, moved = 0, notWeb = 0, already = 0, full = 0
            // A source's bookmarks bar holds what Ikago keeps at its top level.
            let barNames: Set<String> = ["bookmarks bar", "bookmarks toolbar", "favorites", "favourites", "bookmarks menu"]
            for item in data.bookmarks {
                guard AddressResolver.isWebURL(item.url) else { notWeb += 1; continue }
                guard !placed.contains(item.url) else { already += 1; continue }
                // Ikago's own export: its Bookmarks Bar is Ikago's top level, its folders go back under it.
                let path = data.fromIkago && item.folders.first == "Bookmarks Bar" ? Array(item.folders.dropFirst()) : item.folders
                var folder = root
                var depth = 0
                for name in path.prefix(8) where !name.isEmpty {
                    guard root != nil || data.fromIkago, depth == 0 || folder != nil,
                          let next = importFolder(named: name, parent: folder) else { break }
                    folder = next; depth += 1
                }
                placed.insert(item.url)
                // Already at Ikago's top level and headed for the top level (or the source's bookmarks bar): it is where it
                // belongs. Never move someone's own Bookmarks Bar into an "Imported" folder.
                let headedForBar = folder == nil || (path.count == 1 && barNames.contains(path[0].lowercased()))
                if loose[item.url] != nil, headedForBar {
                    loose[item.url] = nil
                    already += 1
                } else if let index = loose.removeValue(forKey: item.url) {
                    bookmarks[index].folderID = folder
                    moved += 1
                } else if bookmarks.count < 5000 {
                    bookmarks.append(Bookmark(url: item.url, title: String(item.title.prefix(512)), folderID: folder))
                    added += 1
                } else {
                    full += 1
                }
            }
            report.items.append(.init(kind: "Bookmarks", noun: "bookmarks", symbol: "bookmark", found: data.bookmarks.count, imported: added + moved,
                                      details: [plural(already, "already in Ikago"), plural(notWeb, "not web addresses"),
                                                plural(full, "over Ikago’s limit of 5,000"),
                                                plural(moved, "earlier imports moved into their folders")].compactMap { $0 }))
        }
        if selection.history, !data.history.isEmpty {
            var urls = Set(history.map(\.url))
            var fresh = Set<String>(), notWeb = 0, already = 0
            for visit in data.history {
                guard AddressResolver.isWebURL(visit.url) else { notWeb += 1; continue }
                guard urls.insert(visit.url).inserted else { already += 1; continue }
                history.append(visit)
                fresh.insert(visit.url)
            }
            history = Array(history.sorted { $0.time > $1.time }.prefix(Session.maxHistory))
            let kept = history.reduce(0) { $0 + (fresh.contains($1.url) ? 1 : 0) }
            report.items.append(.init(kind: "History", noun: "history pages", symbol: "clock", found: data.history.count, imported: kept,
                                      details: [plural(already, "already in your history"), plural(notWeb, "not web addresses"),
                                                plural(fresh.count - kept, "older than Ikago’s most recent \(Session.maxHistory)")].compactMap { $0 }))
        }
        if selection.tabs, !data.tabs.isEmpty {
            let result = mergeImportedTabs(data.tabs, into: spaceID)
            CrashReports.shared.note("imported \(result.tabs) tabs")
            let other = max(0, data.tabs.count - result.tabs - result.limited)
            report.items.append(.init(kind: "Tabs", noun: "tabs", symbol: "square.on.square", found: data.tabs.count, imported: result.tabs,
                                      details: [result.groups > 0 ? "in \(result.groups) groups" : nil,
                                                plural(other, "already open"),
                                                plural(result.limited, "over Ikago’s tab or folder limit (limit was reached)")].compactMap { $0 }))
        }
        scheduleSave()
        if selection.cookies, !data.cookies.isEmpty {
            // Into WebKit always (any launch can reach its store, and per-site engines can send a site there later), and
            // into Chromium when it runs; a later Chromium launch copies WebKit's cookies across (`EngineCookieSync`).
            let store = WebProfiles.dataStore(for: destination.profileID).httpCookieStore
            var added = 0, invalid = 0, rejected = 0
            for item in data.cookies {
                guard let cookie = item.cookie else { invalid += 1; continue }
                if BrowserRuntime.runs(.chromium) {
                    do {
                        try CEFSessions.prepare(destination.profileID)
                        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                            IKCEFContexts.setCookie(cookie, sameSite: Int(item.sameSite), profile: destination.profileID) { error in
                                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                            }
                        }
                    } catch { rejected += 1 }
                }
                await store.setCookie(cookie)
                added += 1
            }
            report.items.append(.init(kind: "Website logins", noun: "website logins", symbol: "person.badge.key", found: data.cookies.count, imported: added,
                                      details: [plural(invalid, "expired or malformed"),
                                                plural(rejected, "kept for WebKit only (Chromium refused them)")].compactMap { $0 }))
        }
        if selection.passwords, !data.passwords.isEmpty || data.passwordsSkipped > 0 {
            let vault = passwordVault ?? PasswordVault.shared
            var added = 0, failure: String?
            do { added = try vault.add(data.passwords) } catch { failure = error.localizedDescription }
            let found = data.passwords.count + data.passwordsSkipped
            report.items.append(.init(kind: "Passwords", noun: "passwords", symbol: "key", found: found, imported: added,
                                      details: [failure.map { "not saved: \($0)" },
                                                failure == nil ? plural(data.passwords.count - added, "already saved") : nil,
                                                plural(data.passwordsSkipped, "without a website or password")].compactMap { $0 }))
        }
        return report
    }

    /// A bookmark folder for imported bookmarks: the existing one with that name in that place, or a new one while
    /// there is room (nil when Ikago's folder limit is reached; the bookmark then stays in the folder above).
    private func importFolder(named name: String, parent: String?) -> String? {
        let name = String(name.prefix(128))
        if let existing = bookmarkFolders.first(where: { $0.name == name && $0.parentID == parent }) { return existing.id }
        guard bookmarkFolders.count < 500 else { return nil }
        let folder = BookmarkFolder(name: name, parentID: parent)
        bookmarkFolders.append(folder)
        return folder.id
    }
}
