import Foundation
import Compression

/// Reads common browser exports, Firefox session backups, and Ikago sessions.
enum ImportFileParser {
    static func read(_ url: URL, chromiumGroupNamespace: String? = nil) throws -> BrowserImportData {
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 64_000_000 else { throw error("Choose an export smaller than 64 MB.") }
        var data = try Data(contentsOf: url)
        // An export archive (Safari's, Ikago's): each file by its kind, as Safari and Chrome read it.
        if data.starts(with: [0x50, 0x4B, 0x03, 0x04]) || data.starts(with: [0x50, 0x4B, 0x05, 0x06]) { return try archive(data) }
        if url.pathExtension.lowercased() == "csv" { return try passwordsCSV(data) }
        if data.starts(with: Array("mozLz40\0".utf8)) { data = try decompressFirefox(data) }
        if data.starts(with: Array("SNSS".utf8)) { return BrowserImportData(tabs: try ChromiumSessionParser.read(data, groupNamespace: chromiumGroupNamespace ?? url.standardizedFileURL.path)) }
        if ["html", "htm"].contains(url.pathExtension.lowercased()) { return try bookmarksHTML(data) }
        if url.pathExtension.lowercased() == "plist" {
            let object = try PropertyListSerialization.propertyList(from: data, format: nil)
            var result = BrowserImportData(); collectBookmarks(object, into: &result); return result
        }
        if let object = try? JSONSerialization.jsonObject(with: data) {
            let result = json(object)
            guard result.hasData else { throw error("This JSON file contains no supported bookmarks, history, tabs or cookies.") }
            return result
        }
        if let text = String(data: data, encoding: .utf8), text.contains("\t") { return cookiesText(text) }
        throw error("Choose a browser’s export (ZIP, bookmarks HTML, history JSON, passwords CSV), a browser session file, or a cookie export.")
    }

    /// Safari's export archive (and Ikago's, which uses its format): bookmarks HTML, history JSON and passwords CSV, each
    /// found by their file extension. Files it doesn't know (extensions, payment cards) are left alone.
    static func archive(_ data: Data) throws -> BrowserImportData {
        var result = BrowserImportData()
        var known = 0
        for entry in try ZipArchive.read(data) {
            let name = entry.name.lowercased()
            do {
                if name.hasSuffix(".html") || name.hasSuffix(".htm") {
                    result.merge(try bookmarksHTML(entry.data)); known += 1
                } else if name.hasSuffix(".csv") {
                    result.merge(try passwordsCSV(entry.data)); known += 1
                } else if name.hasSuffix(".json"), let object = try? JSONSerialization.jsonObject(with: entry.data) {
                    let part = json(object)
                    if part.hasData { result.merge(part); known += 1 }
                }
            } catch {
                result.notes.append("\(entry.name): \(error.localizedDescription)")
            }
        }
        guard known > 0 || !result.notes.isEmpty else { throw error("This archive has no bookmarks, history or passwords Ikago can read.") }
        return result
    }

    /// A passwords export (Apple Passwords, Safari, Chrome, Firefox, password managers): columns found by name.
    static func passwordsCSV(_ data: Data) throws -> BrowserImportData {
        guard let text = String(data: data, encoding: .utf8) else { throw error("The passwords file is not UTF-8.") }
        let parsed = try PasswordImport.parse(text)
        var result = BrowserImportData()
        result.passwords = parsed.logins
        result.passwordsSkipped = parsed.skipped
        return result
    }

    static func json(_ object: Any) -> BrowserImportData {
        var result = BrowserImportData()
        if let list = object as? [[String: Any]], list.first?["domain"] != nil {
            result.cookies = list.compactMap(cookie); return result
        }
        guard let root = object as? [String: Any] else { return result }
        if root["roots"] != nil { collectBookmarks(root["roots"]!, into: &result) }
        if let bookmarks = root["bookmarks"] { collectBookmarks(bookmarks, into: &result) }
        if let cookies = root["cookies"] as? [[String: Any]] { result.cookies = cookies.compactMap(cookie) }
        let folderNames = Dictionary((root["folders"] as? [[String: Any]] ?? []).compactMap { row -> (String, String)? in
            guard let id = row["id"] as? String, let name = row["name"] as? String else { return nil }; return (id, name)
        }, uniquingKeysWith: { first, _ in first })
        if let tabs = root["tabs"] as? [[String: Any]] {
            result.tabs = tabs.compactMap { tab in
                guard let url = tab["url"] as? String, AddressResolver.isWebURL(url) else { return nil }
                return ImportTab(url: url, title: String((tab["title"] as? String ?? url).prefix(512)), pinned: tab["pinned"] as? Bool ?? false,
                                 group: (tab["folder"] as? String).flatMap { folderNames[$0] })
            }
        }
        for window in root["windows"] as? [[String: Any]] ?? [] {
            for tab in window["tabs"] as? [[String: Any]] ?? [] {
                let entries = tab["entries"] as? [[String: Any]] ?? []
                let index = min(max(0, (tab["index"] as? Int ?? entries.count) - 1), max(0, entries.count - 1))
                guard entries.indices.contains(index), let url = entries[index]["url"] as? String, AddressResolver.isWebURL(url) else { continue }
                result.tabs.append(ImportTab(url: url, title: String((entries[index]["title"] as? String ?? url).prefix(512)), pinned: tab["pinned"] as? Bool ?? false))
            }
        }
        // Safari's export ("history", times in microseconds), Chrome's data portability format ("history_visits"), and
        // Ikago's older sessions ("history", "time" in milliseconds).
        if let visits = (root["history"] ?? root["history_visits"]) as? [[String: Any]] {
            result.history = visits.compactMap { row in
                guard let url = row["url"] as? String, AddressResolver.isWebURL(url) else { return nil }
                // The file decides these numbers: keep them in a range every later use can take, never trap on them.
                func number(_ key: String) -> UInt64? {
                    (row[key] as? NSNumber).map { let value = $0.doubleValue; return value.isFinite ? UInt64(min(max(0, value), 9e15)) : 0 }
                }
                let time = number("time") ?? number("time_usec").map { $0 / 1000 } ?? number("visit_time_unix_epoch_usec").map { $0 / 1000 } ?? 0
                let title = (row["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? url
                return Visit(url: url, title: String(title.prefix(512)), time: time,
                             visits: number("visit_count").map { Int(min($0, 1_000_000)) } ?? number("visits").map { Int(min($0, 1_000_000)) },
                             typed: number("typed_count").map { Int(min($0, 1_000_000)) } ?? number("typed").map { Int(min($0, 1_000_000)) })
            }
        }
        return result
    }

    /// Bookmarks with their folders from Chrome's `Bookmarks` JSON, Safari's `Bookmarks.plist` and similar exports.
    static func collectBookmarks(_ object: Any, into result: inout BrowserImportData, path: [String] = [], depth: Int = 0) {
        guard depth < 64, result.bookmarks.count < 5000 else { return }
        if let list = object as? [Any] {
            for child in list { collectBookmarks(child, into: &result, path: path, depth: depth + 1) }
            return
        }
        guard let row = object as? [String: Any] else { return }
        if let url = (row["url"] ?? row["URLString"]) as? String, AddressResolver.isWebURL(url) {
            let title = row["name"] as? String ?? row["title"] as? String ?? (row["URIDictionary"] as? [String: Any])?["title"] as? String ?? url
            result.bookmarks.append(ImportedBookmark(url: url, title: String(title.prefix(512)), folders: path))
            return
        }
        // Safari: lists are folders; the top-level ones have internal names. History (a proxy) has no bookmarks.
        if let type = row["WebBookmarkType"] as? String {
            guard type == "WebBookmarkTypeList", let children = row["Children"] else { return }
            let title = row["Title"] as? String ?? ""
            let names = ["BookmarksBar": "Favorites", "BookmarksMenu": "Bookmarks Menu", "com.apple.ReadingList": "Reading List"]
            let name = names[title] ?? title
            collectBookmarks(children, into: &result, path: name.isEmpty ? path : path + [name], depth: depth + 1)
            return
        }
        // Chrome: folders have a name and children ("Bookmarks bar", "Other bookmarks" at the top).
        if row["type"] as? String == "folder", let children = row["children"] {
            let name = row["name"] as? String ?? ""
            collectBookmarks(children, into: &result, path: name.isEmpty ? path : path + [name], depth: depth + 1)
            return
        }
        // Chrome's roots and other containers, in a stable order.
        for key in row.keys.sorted(by: Self.rootOrder) {
            let value = row[key]!
            if value is [Any] || value is [String: Any] { collectBookmarks(value, into: &result, path: path, depth: depth + 1) }
        }
    }

    private static func rootOrder(_ a: String, _ b: String) -> Bool {
        let order = ["bookmark_bar": 0, "other": 1, "synced": 2]
        return (order[a] ?? 3, a) < (order[b] ?? 3, b)
    }

    /// Chrome's `Bookmarks` file. A profile without bookmarks is a normal result, not an error.
    static func chromiumBookmarks(_ url: URL) throws -> [ImportedBookmark] {
        let data = try Data(contentsOf: url)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], let roots = root["roots"] else {
            throw error("Chrome’s bookmarks file has an unexpected format.")
        }
        var result = BrowserImportData()
        collectBookmarks(roots, into: &result)
        return result.bookmarks
    }

    /// Safari's `Cookies.binarycookies`: big-endian page table, then pages of little-endian cookie records whose strings
    /// are NUL-terminated at offsets from the record's start, and whose dates count from 2001.
    static func safariCookies(_ data: Data) throws -> [ImportedCookie] {
        let bytes = [UInt8](data)
        func be32(_ at: Int) -> Int { at + 4 <= bytes.count ? Int(bytes[at]) << 24 | Int(bytes[at + 1]) << 16 | Int(bytes[at + 2]) << 8 | Int(bytes[at + 3]) : 0 }
        func le32(_ at: Int) -> Int { at + 4 <= bytes.count ? Int(bytes[at]) | Int(bytes[at + 1]) << 8 | Int(bytes[at + 2]) << 16 | Int(bytes[at + 3]) << 24 : 0 }
        func double(_ at: Int) -> Double {
            guard at + 8 <= bytes.count else { return 0 }
            var raw: UInt64 = 0
            for index in 0..<8 { raw |= UInt64(bytes[at + index]) << (8 * UInt64(index)) }
            return Double(bitPattern: raw)
        }
        func string(_ at: Int, limit: Int) -> String? {
            guard at >= 0, at < limit else { return nil }
            var end = at
            while end < limit, bytes[end] != 0 { end += 1 }
            return String(decoding: bytes[at..<end], as: UTF8.self)
        }
        guard bytes.count >= 8, Array(bytes.prefix(4)) == Array("cook".utf8) else { throw error("Safari’s cookie file has an unexpected format.") }
        let pages = be32(4)
        guard pages >= 0, pages < 100_000 else { throw error("Safari’s cookie file is damaged.") }
        var cookies: [ImportedCookie] = []
        var page = 8 + pages * 4
        for index in 0..<pages {
            let size = be32(8 + index * 4)
            defer { page += size }
            guard size > 8, page + size <= bytes.count else { break }
            let count = le32(page + 4)
            for slot in 0..<min(count, 10_000) {
                let start = page + le32(page + 8 + slot * 4)
                let length = le32(start)
                guard length >= 56, start + length <= page + size else { continue }
                let end = start + length
                let flags = le32(start + 8)
                guard let domain = string(start + le32(start + 16), limit: end), let name = string(start + le32(start + 20), limit: end),
                      let path = string(start + le32(start + 24), limit: end), let value = string(start + le32(start + 28), limit: end)
                else { continue }
                let expiry = double(start + 40)
                cookies.append(ImportedCookie(domain: domain, path: path.isEmpty ? "/" : path, name: name, value: value,
                                              secure: flags & 1 != 0, httpOnly: flags & 4 != 0,
                                              expires: (1...1e11).contains(expiry) ? Date(timeIntervalSinceReferenceDate: expiry) : nil))
                if cookies.count >= 50_000 { return cookies }
            }
        }
        return cookies
    }

    static func cookie(_ row: [String: Any]) -> ImportedCookie? {
        guard let domain = row["domain"] as? String, let name = row["name"] as? String, let value = row["value"] as? String else { return nil }
        let expiry = (row["expirationDate"] ?? row["expires"]) as? NSNumber
        return ImportedCookie(domain: domain, path: row["path"] as? String ?? "/", name: name, value: value,
                              secure: row["secure"] as? Bool ?? false, httpOnly: row["httpOnly"] as? Bool ?? false,
                              expires: expiry.flatMap { (1...1e11).contains($0.doubleValue) ? Date(timeIntervalSince1970: $0.doubleValue) : nil })
    }

    private static func cookiesText(_ text: String) -> BrowserImportData {
        var result = BrowserImportData()
        for raw in text.split(whereSeparator: \.isNewline).prefix(50_000) {
            var line = String(raw)
            let httpOnly = line.hasPrefix("#HttpOnly_")
            if httpOnly { line.removeFirst(10) }
            if line.hasPrefix("#") { continue }
            let fields = line.components(separatedBy: "\t")
            guard fields.count >= 7 else { continue }
            let expiry = Double(fields[4]) ?? 0
            result.cookies.append(ImportedCookie(domain: fields[0], path: fields[2], name: fields[5], value: fields[6...].joined(separator: "\t"),
                                                   secure: fields[3].uppercased() == "TRUE", httpOnly: httpOnly,
                                                   expires: expiry > 0 ? Date(timeIntervalSince1970: expiry) : nil))
        }
        return result
    }

    /// Netscape bookmark HTML (every browser's export): `<DT><H3>` names a folder whose `<DL>` holds its items.
    private static func bookmarksHTML(_ data: Data) throws -> BrowserImportData {
        guard let text = String(data: data, encoding: .utf8) else { throw error("The bookmarks file is not UTF-8.") }
        let pattern = #"<h3\b[^>]*>(.*?)</h3\s*>|<dl\b[^>]*>|</dl\s*>|<a\b[^>]*\bhref\s*=\s*["']([^"']+)["'][^>]*>(.*?)</a\s*>"#
        let expression = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
        let ns = text as NSString
        var result = BrowserImportData()
        var stack: [String] = [], pending: String?
        func plain(_ range: NSRange) -> String {
            entities(ns.substring(with: range).replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for match in expression.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let token = ns.substring(with: match.range).prefix(4).lowercased()
            if match.range(at: 1).location != NSNotFound {
                pending = plain(match.range(at: 1))
            } else if token.hasPrefix("<dl") {
                stack.append(pending ?? ""); pending = nil
            } else if token.hasPrefix("</dl") {
                if !stack.isEmpty { stack.removeLast() }
            } else if match.range(at: 2).location != NSNotFound, result.bookmarks.count < 5000 {
                let url = entities(ns.substring(with: match.range(at: 2)))
                guard AddressResolver.isWebURL(url) else { continue }
                result.bookmarks.append(ImportedBookmark(url: url, title: String(plain(match.range(at: 3)).prefix(512)),
                                                         folders: stack.filter { !$0.isEmpty }))
            }
        }
        result.fromIkago = text.contains(BrowserExport.ikagoMarker)
        return result
    }

    /// Named and numeric character references (`&amp;`, `&#233;`, `&#x27;`), with `&amp;` last so it never makes a new one.
    static func entities(_ value: String) -> String {
        guard value.contains("&") else { return value }
        var result = value
        for (encoded, plain) in [("&quot;", "\""), ("&apos;", "'"), ("&nbsp;", "\u{00A0}"), ("&lt;", "<"), ("&gt;", ">")] {
            result = result.replacingOccurrences(of: encoded, with: plain)
        }
        if result.contains("&#"), let expression = try? NSRegularExpression(pattern: "&#([xX][0-9a-fA-F]{1,6}|[0-9]{1,7});") {
            let ns = result as NSString
            var output = "", last = 0
            for match in expression.matches(in: result, range: NSRange(location: 0, length: ns.length)) {
                output += ns.substring(with: NSRange(location: last, length: match.range.location - last))
                let digits = ns.substring(with: match.range(at: 1))
                let code = digits.lowercased().hasPrefix("x") ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits)
                output += code.flatMap(Unicode.Scalar.init).map { String(Character($0)) } ?? ns.substring(with: match.range)
                last = match.range.location + match.range.length
            }
            result = output + ns.substring(from: last)
        }
        return result.replacingOccurrences(of: "&amp;", with: "&")
    }

    private static func decompressFirefox(_ data: Data) throws -> Data {
        guard data.count >= 12 else { throw error("The Firefox session is truncated.") }
        let bytes = [UInt8](data)
        let size = Int(bytes[8]) | Int(bytes[9]) << 8 | Int(bytes[10]) << 16 | Int(bytes[11]) << 24
        guard size > 0, size <= 64_000_000 else { throw error("The Firefox session is too large or damaged.") }
        var output = [UInt8](repeating: 0, count: size)
        let decoded = output.withUnsafeMutableBufferPointer { destination in
            bytes.withUnsafeBufferPointer { source in
                compression_decode_buffer(destination.baseAddress!, size, source.baseAddress! + 12, bytes.count - 12, nil, COMPRESSION_LZ4_RAW)
            }
        }
        guard decoded == size else { throw error("The Firefox session could not be decompressed.") }
        return Data(output)
    }

    static func error(_ text: String) -> NSError { NSError(domain: "Ikago.Import", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
}
