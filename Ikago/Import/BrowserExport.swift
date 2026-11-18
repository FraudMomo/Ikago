import Foundation

/// Ikago's data in formats other browsers import, so leaving Ikago never means losing anything:
/// - Bookmarks as a Netscape bookmarks file (`Bookmarks.html`), which every browser imports, folders included.
/// - Everything as Safari's export archive: `Bookmarks.html`, `History.json` (Safari's history format) and, when chosen,
///   `Passwords.csv` (Apple Passwords' columns). Safari imports it (File ▸ Import From ▸ File or Folder), and Chrome reads
///   the same archive (it finds each part by extension, and history by `metadata.data_type`).
enum BrowserExport {
    struct Password: Equatable {
        var title: String
        var url: String
        var username: String
        var password: String
    }

    static let bookmarksName = "Bookmarks.html"
    static let historyName = "History.json"
    static let passwordsName = "Passwords.csv"
    /// A comment other browsers ignore; Ikago reads it to restore its own export as it was (`BrowserImportData.fromIkago`).
    static let ikagoMarker = "<!-- Exported by Ikago -->"

    // MARK: Bookmarks

    /// The bookmarks in their folders. Ikago's top level is its Bookmarks Bar, so it goes in a folder marked as the
    /// toolbar: Chrome and Firefox put it in their bookmarks bar, Safari in its Favorites.
    static func bookmarksHTML(_ bookmarks: [Bookmark], folders: [BookmarkFolder], date: Date = Date()) -> String {
        let stamp = String(Int(date.timeIntervalSince1970))
        let known = Set(folders.map(\.id))
        var children: [String?: [BookmarkFolder]] = [:]
        for folder in folders { children[folder.parentID.flatMap { known.contains($0) ? $0 : nil }, default: []].append(folder) }
        var items: [String?: [Bookmark]] = [:]
        for bookmark in bookmarks where AddressResolver.isWebURL(bookmark.url) {
            items[bookmark.folderID.flatMap { known.contains($0) ? $0 : nil }, default: []].append(bookmark)
        }
        var lines = ["<!DOCTYPE NETSCAPE-Bookmark-file-1>",
                     ikagoMarker,
                     "<!-- This is an automatically generated file.",
                     "     It will be read and overwritten.",
                     "     DO NOT EDIT! -->",
                     "<META HTTP-EQUIV=\"Content-Type\" CONTENT=\"text/html; charset=UTF-8\">",
                     "<TITLE>Bookmarks</TITLE>",
                     "<H1>Bookmarks</H1>",
                     "<DL><p>"]
        var visited = Set<String>()
        func folder(_ id: String?, name: String, depth: Int, toolbar: Bool = false) {
            let pad = String(repeating: "    ", count: depth)
            lines.append("\(pad)<DT><H3 ADD_DATE=\"\(stamp)\" LAST_MODIFIED=\"\(stamp)\"\(toolbar ? " PERSONAL_TOOLBAR_FOLDER=\"true\"" : "")>\(escape(name))</H3>")
            lines.append("\(pad)<DL><p>")
            // Folders first, like Ikago's lists; depth is capped, as Ikago's own folders are.
            if depth < 32 {
                for child in children[id] ?? [] where visited.insert(child.id).inserted {
                    folder(child.id, name: child.name, depth: depth + 1)
                }
            }
            for bookmark in items[id] ?? [] {
                let title = bookmark.title.isEmpty ? bookmark.url : bookmark.title
                lines.append("\(pad)    <DT><A HREF=\"\(escape(bookmark.url))\" ADD_DATE=\"\(stamp)\">\(escape(title))</A>")
            }
            lines.append("\(pad)</DL><p>")
        }
        folder(nil, name: "Bookmarks Bar", depth: 1, toolbar: true)
        lines.append("</DL><p>")
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: History

    /// Safari's `History.json`: metadata first (Chrome's reader requires that order), then one entry per page.
    static func historyJSON(_ visits: [Visit], date: Date = Date()) -> String {
        let metadata: [String: Any] = ["browser_name": "Ikago", "browser_version": appVersion, "data_type": "history",
                                       "export_time_usec": Int64(date.timeIntervalSince1970 * 1_000_000), "schema_version": 1]
        let entries: [String] = visits.compactMap { visit in
            guard AddressResolver.isWebURL(visit.url) else { return nil }
            let entry: [String: Any] = ["url": visit.url, "title": visit.title,
                                        "time_usec": Int64(visit.time) * 1000, "visit_count": max(1, visit.visits ?? 1)]
            return json(entry)
        }
        return "{\"metadata\":\(json(metadata)),\"history\":[\(entries.joined(separator: ","))]}"
    }

    // MARK: Passwords

    /// Apple Passwords' columns, which Safari, Chrome and Firefox all read (they find columns by name).
    static func passwordsCSV(_ passwords: [Password]) -> String {
        var csv = "Title,URL,Username,Password,Notes,OTPAuth\n"
        for row in passwords {
            csv += [row.title, row.url, row.username, row.password, "", ""].map(csvField).joined(separator: ",") + "\n"
        }
        return csv
    }

    /// RFC 4180: always quoted, quotes doubled.
    static func csvField(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }

    // MARK: Archive

    static func archive(bookmarks: String?, history: String?, passwords: String?, date: Date = Date()) -> Data {
        var entries: [ZipArchive.Entry] = []
        if let bookmarks { entries.append(.init(name: bookmarksName, data: Data(bookmarks.utf8))) }
        if let history { entries.append(.init(name: historyName, data: Data(history.utf8))) }
        if let passwords { entries.append(.init(name: passwordsName, data: Data(passwords.utf8))) }
        return ZipArchive.write(entries, date: date)
    }

    /// Writes a file readable by its owner only, replacing one already there.
    static func save(_ data: Data, to url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        guard FileManager.default.createFile(atPath: url.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    // MARK: Helpers

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func json(_ object: Any) -> String {
        (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]))
            .map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }

    private static var appVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "" }
}
