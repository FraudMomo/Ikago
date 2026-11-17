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
    var notes: [String] = []
    var accessIssues: [String] = []
    /// The browser it came from, for the "Imported from …" bookmark folder.
    var sourceName = ""
    var hasData: Bool { !bookmarks.isEmpty || !history.isEmpty || !tabs.isEmpty || !cookies.isEmpty }
}

struct ImportSelection: Sendable {
    var bookmarks = true
    var history = true
    var tabs = true
    var cookies = false
}

extension BrowserState {
    /// Merge only the selected data. Imported identities never overwrite an existing tab or Space.
    func applyImport(_ data: BrowserImportData, selection: ImportSelection, to spaceID: UUID) async -> String {
        guard !isFrozen else { return "Import stopped because Ikago is closing." }
        guard let destination = spaces.first(where: { $0.id == spaceID }) else { return "The destination Space was removed. Choose another Space." }
        var addedBookmarks = 0, movedBookmarks = 0, addedTabs = 0, addedCookies = 0, failedCookies = 0
        if selection.bookmarks, !data.bookmarks.isEmpty {
            // Like Chrome: everything goes into one "Imported from …" folder with the source's own folders inside it.
            // Importing again reuses those folders and skips bookmarks already in the same folder.
            let root = importFolder(named: data.sourceName.isEmpty ? "Imported" : "Imported from \(data.sourceName)", parent: nil)
            // Importing again is safe: a bookmark already in some folder is kept where it is, and one left at the top
            // level (earlier imports brought everything in flat) moves into its folder instead of being copied.
            let known = Set(bookmarkFolders.map(\.id))
            var placed = Set(bookmarks.filter { $0.folderID.map(known.contains) ?? false }.map(\.url))
            var loose: [String: Int] = [:]
            for (index, bookmark) in bookmarks.enumerated() where !(bookmark.folderID.map(known.contains) ?? false) {
                loose[bookmark.url] = loose[bookmark.url] ?? index
            }
            for item in data.bookmarks where AddressResolver.isWebURL(item.url) && !placed.contains(item.url) {
                var folder = root
                for name in item.folders.prefix(8) where !name.isEmpty {
                    guard let parent = folder, let next = importFolder(named: name, parent: parent) else { break }
                    folder = next
                }
                placed.insert(item.url)
                if let index = loose.removeValue(forKey: item.url) {
                    bookmarks[index].folderID = folder
                    movedBookmarks += 1
                } else if bookmarks.count < 5000 {
                    bookmarks.append(Bookmark(url: item.url, title: String(item.title.prefix(512)), folderID: folder))
                    addedBookmarks += 1
                }
            }
        }
        if selection.history {
            var urls = Set(history.map(\.url))
            for visit in data.history where AddressResolver.isWebURL(visit.url) && urls.insert(visit.url).inserted {
                history.append(visit)
            }
            history = Array(history.sorted { $0.time > $1.time }.prefix(Session.maxHistory))
        }
        var addedGroups = 0, limitedTabs = 0
        if selection.tabs {
            let result = mergeImportedTabs(data.tabs, into: spaceID)
            addedTabs = result.tabs; addedGroups = result.groups; limitedTabs = result.limited
        }
        scheduleSave()
        if selection.cookies {
            // Into every engine this launch runs, so imported logins work whichever engine a site uses.
            let store = BrowserRuntime.runs(.webkit) ? WebProfiles.dataStore(for: destination.profileID).httpCookieStore : nil
            for item in data.cookies {
                guard let cookie = item.cookie else { continue }
                var added = false
                if BrowserRuntime.runs(.chromium) {
                    do {
                        try CEFSessions.prepare(destination.profileID)
                        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                            IKCEFContexts.setCookie(cookie, sameSite: Int(item.sameSite), profile: destination.profileID) { error in
                                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                            }
                        }
                        added = true
                    } catch { failedCookies += 1 }
                }
                if let store { await store.setCookie(cookie); added = true }
                if added { addedCookies += 1 }
            }
        }
        let limitNote = limitedTabs > 0 ? " Skipped \(limitedTabs) additional tabs because Ikago’s tab or folder limit was reached." : ""
        let movedNote = movedBookmarks > 0 ? " Moved \(movedBookmarks) earlier imported bookmarks into their folders." : ""
        return "Imported \(addedBookmarks) bookmarks, \(addedTabs) tabs, \(addedGroups) groups and \(addedCookies) cookies.\(selection.history ? " History merged." : "") Duplicates were skipped; existing data was kept.\(limitNote)\(movedNote)\(failedCookies > 0 ? " Partial import: \(failedCookies) cookies were rejected by the destination engine." : "")"
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
