import Foundation

/// Source files are opened read-only. The browser should be closed for a stable session snapshot.
enum BrowserProfileImporter {
    enum Kind: String, CaseIterable, Identifiable, Sendable {
        case chromium = "Chrome / Edge / Brave / Arc", firefox = "Firefox / Zen", safari = "Safari", file = "Export or session file"
        var id: String { rawValue }
    }

    static func read(_ url: URL, kind: Kind, decryptWith browser: ChromiumCookieCrypto.Browser?) throws -> BrowserImportData {
        if kind == .file { return try ImportFileParser.read(url) }
        var result = BrowserImportData()
        func attempt(_ file: String, _ body: (URL) throws -> Void) {
            let path = url.appending(path: file)
            do { try body(path) }
            catch {
                guard !ImportAccessError.isMissing(error) else { return }
                if ImportAccessError.isPermissionDenied(error) { result.accessIssues.append(file) }
                result.notes.append("\(file): \(error.localizedDescription)")
            }
        }
        switch kind {
        case .chromium:
            attempt("Bookmarks") { result.bookmarks = try ImportFileParser.read($0).bookmarks }
            attempt("History") { path in
                let rows = try ImportDatabase(path).rows("SELECT url, title, last_visit_time FROM urls ORDER BY last_visit_time DESC LIMIT 1000")
                result.history = rows.compactMap { row in
                    guard let address = row["url"] as? String, AddressResolver.isWebURL(address) else { return nil }
                    let unix = ((row["last_visit_time"] as? Int64 ?? 0) / 1000) - 11_644_473_600_000
                    return Visit(url: address, title: String((row["title"] as? String ?? address).prefix(512)), time: UInt64(max(0, unix)))
                }
            }
            let cookiePath = FileManager.default.fileExists(atPath: url.appending(path: "Network/Cookies").path) ? "Network/Cookies" : "Cookies"
            attempt(cookiePath) { path in
                let db = try ImportDatabase(path)
                // Keep SameSite so imported logins stay as CSRF-resistant as in the source browser (older profiles lack the column).
                let rows = try (try? db.rows("SELECT host_key, name, value, encrypted_value, path, expires_utc, is_secure, is_httponly, samesite FROM cookies LIMIT 50000"))
                    ?? db.rows("SELECT host_key, name, value, encrypted_value, path, expires_utc, is_secure, is_httponly FROM cookies LIMIT 50000")
                let version = Int((try? db.rows("SELECT value FROM meta WHERE key='version'").first?["value"] as? String) ?? "0") ?? 0
                var key: Data?
                if rows.contains(where: { !(($0["encrypted_value"] as? Data) ?? Data()).isEmpty }), let browser {
                    do { key = try ChromiumCookieCrypto.key(for: browser) } catch { result.notes.append(error.localizedDescription) }
                }
                var skipped = 0
                for row in rows {
                    guard let domain = row["host_key"] as? String, let name = row["name"] as? String else { continue }
                    let encrypted = row["encrypted_value"] as? Data ?? Data()
                    var value = row["value"] as? String ?? ""
                    if !encrypted.isEmpty {
                        guard let key, let decrypted = ChromiumCookieCrypto.decrypt(encrypted, key: key, domain: domain, databaseVersion: version) else { skipped += 1; continue }
                        value = decrypted
                    }
                    let expiry = Double(row["expires_utc"] as? Int64 ?? 0) / 1_000_000 - 11_644_473_600
                    let cookie = ImportedCookie(domain: domain, path: row["path"] as? String ?? "/", name: name, value: value,
                                                secure: row["is_secure"] as? Int64 == 1, httpOnly: row["is_httponly"] as? Int64 == 1,
                                                expires: expiry > 0 ? Date(timeIntervalSince1970: expiry) : nil,
                                                sameSite: row["samesite"] as? Int64 ?? -1)
                    if cookie.cookie != nil { result.cookies.append(cookie) }
                }
                if skipped > 0 { result.notes.append("\(skipped) encrypted cookies were skipped. Some website logins could not be transferred; you may need to sign in again.") }
            }
            var files: [URL] = []
            attempt("Sessions") { directory in
                files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                    .filter { $0.lastPathComponent.hasPrefix("Session_") }.sorted { $0.lastPathComponent > $1.lastPathComponent }
            }
            if let file = files.first {
                attempt("Sessions/\(file.lastPathComponent)") {
                    result.tabs = try ImportFileParser.read($0, chromiumGroupNamespace: url.standardizedFileURL.path).tabs
                }
            } else { attempt("Current Session") { result.tabs = try ImportFileParser.read($0, chromiumGroupNamespace: url.standardizedFileURL.path).tabs } }
        case .firefox:
            attempt("places.sqlite") { path in
                let db = try ImportDatabase(path)
                let bookmarks = try db.rows("SELECT p.url, COALESCE(b.title,p.title,'') AS title FROM moz_bookmarks b JOIN moz_places p ON b.fk=p.id WHERE b.type=1 LIMIT 5000")
                result.bookmarks = bookmarks.compactMap { row in
                    guard let address = row["url"] as? String, AddressResolver.isWebURL(address) else { return nil }
                    return Bookmark(url: address, title: String((row["title"] as? String ?? address).prefix(512)))
                }
                result.history = try db.rows("SELECT url, COALESCE(title,'') AS title, last_visit_date FROM moz_places WHERE last_visit_date IS NOT NULL ORDER BY last_visit_date DESC LIMIT 1000").compactMap { row in
                    guard let address = row["url"] as? String, AddressResolver.isWebURL(address) else { return nil }
                    return Visit(url: address, title: String((row["title"] as? String ?? address).prefix(512)), time: UInt64(max(0, (row["last_visit_date"] as? Int64 ?? 0) / 1000)))
                }
            }
            attempt("cookies.sqlite") { path in
                let db = try ImportDatabase(path)
                let rows = try (try? db.rows("SELECT host, path, name, value, expiry, isSecure, isHttpOnly, sameSite FROM moz_cookies LIMIT 50000"))
                    ?? db.rows("SELECT host, path, name, value, expiry, isSecure, isHttpOnly FROM moz_cookies LIMIT 50000")
                result.cookies = rows.compactMap { row in
                    guard let domain = row["host"] as? String, let name = row["name"] as? String, let value = row["value"] as? String else { return nil }
                    let expiry = Double(row["expiry"] as? Int64 ?? 0)
                    return ImportedCookie(domain: domain, path: row["path"] as? String ?? "/", name: name, value: value,
                                          secure: row["isSecure"] as? Int64 == 1, httpOnly: row["isHttpOnly"] as? Int64 == 1,
                                          expires: expiry > 0 ? Date(timeIntervalSince1970: expiry) : nil,
                                          sameSite: row["sameSite"] as? Int64 ?? -1)
                }
            }
            for file in ["sessionstore.jsonlz4", "sessionstore-backups/recovery.jsonlz4", "sessionstore-backups/previous.jsonlz4"] where result.tabs.isEmpty {
                attempt(file) { result.tabs = try ImportFileParser.read($0).tabs }
            }
        case .safari:
            attempt("Bookmarks.plist") { result.bookmarks = try ImportFileParser.read($0).bookmarks }
            attempt("History.db") { path in
                result.history = try ImportDatabase(path).rows("SELECT i.url, v.title, v.visit_time FROM history_visits v JOIN history_items i ON v.history_item=i.id ORDER BY v.visit_time DESC LIMIT 1000").compactMap { row in
                    guard let address = row["url"] as? String, AddressResolver.isWebURL(address) else { return nil }
                    let seconds = (row["visit_time"] as? Double ?? 0) + 978_307_200
                    return Visit(url: address, title: String((row["title"] as? String ?? address).prefix(512)), time: UInt64(max(0, seconds * 1000)))
                }
            }
            result.notes.append("Safari cookies and open tabs require an exported file. Select Export or session file to import cookie JSON/Netscape text or a session export.")
        case .file: break
        }
        if kind == .chromium, !result.tabs.isEmpty {
            result.notes.append("Open tabs preserve URLs, titles and pins. Open tab groups become Ikago folders with their names, colors and collapsed state. Navigation history and closed saved groups are not copied.")
        }
        if !result.hasData { result.notes.append("No available browser data could be read. macOS may need to allow Ikago access to this browser’s data.") }
        return result
    }
}
