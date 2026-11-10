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
    var bookmarks: [Bookmark] = []
    var history: [Visit] = []
    var tabs: [ImportTab] = []
    var cookies: [ImportedCookie] = []
    var notes: [String] = []
    var accessIssues: [String] = []
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
        var addedBookmarks = 0, addedTabs = 0, addedCookies = 0, failedCookies = 0
        if selection.bookmarks {
            var urls = Set(bookmarks.map(\.url))
            for item in data.bookmarks where bookmarks.count < 5000 && AddressResolver.isWebURL(item.url) && urls.insert(item.url).inserted {
                bookmarks.append(Bookmark(url: item.url, title: String(item.title.prefix(512))))
                addedBookmarks += 1
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
        return "Imported \(addedBookmarks) bookmarks, \(addedTabs) tabs, \(addedGroups) groups and \(addedCookies) cookies.\(selection.history ? " History merged." : "") Duplicates were skipped; existing data was kept.\(limitNote)\(failedCookies > 0 ? " Partial import: \(failedCookies) cookies were rejected by the destination engine." : "")"
    }
}
