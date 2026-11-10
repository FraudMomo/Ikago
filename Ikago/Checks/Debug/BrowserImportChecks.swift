#if DEBUG
import Foundation
import SQLite3
import Compression

@MainActor
enum BrowserImportChecks {
    static func run(_ browser: BrowserWindowController) async {
        var failures = 0
        func check(_ value: Bool, _ name: String) {
            print("IKTEST import \(value ? "PASS" : "FAIL") \(name)")
            if !value { failures += 1 }
        }
        let root = FileManager.default.temporaryDirectory.appending(path: "IkagoImportChecks-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let html = root.appending(path: "bookmarks.html")
            try Data("<DL><DT><A HREF=\"https://example.com/?a=1&amp;b=2\">One &amp; Two</A><A HREF='javascript:alert(1)'>Unsafe</A></DL>".utf8).write(to: html)
            let bookmarkData = try ImportFileParser.read(html)
            check(bookmarkData.bookmarks.count == 1 && bookmarkData.bookmarks[0].title == "One & Two", "HTML bookmarks decode entities and reject executable URLs")
            let json: [String: Any] = ["tabs": [["url": "https://example.org", "title": "Tab", "folder": "group"]],
                                      "folders": [["id": "group", "name": "Work"]],
                                      "cookies": [["domain": ".example.com", "name": "session", "value": "fixture", "httpOnly": true, "secure": true]]]
            let parsed = ImportFileParser.json(json)
            check(parsed.tabs.first?.group == "Work" && parsed.cookies.first?.cookie?.isHTTPOnly == true && parsed.cookies.first?.cookie?.isSecure == true, "session groups and cookie security flags retained")
            // Independent vector: PBKDF2-SHA1 (saltysalt, 1003 rounds) and AES-128-CBC, computed with OpenSSL.
            let key = try ChromiumCookieCrypto.derive(password: Data("ikago-test".utf8))
            check(key.map { String(format: "%02x", $0) }.joined() == "57929fbe2a75a951553979f155f4b5b7", "Chromium PBKDF2 matches independent vector")
            let encrypted = Data(base64Encoded: "djEwS2f2shNP/OOeIO+ZIlTxMrCbpBq4Ijs4VHwsZb4r47lsDnZCWc3oLCuDCAK80UO0")!
            check(ChromiumCookieCrypto.decrypt(encrypted, key: key, domain: ".example.com", databaseVersion: 24) == "fixture-cookie", "Chromium v10 AES cookie decryption matches independent vector")
            check(ChromiumCookieCrypto.decrypt(encrypted, key: key, domain: ".other.com", databaseVersion: 24) == nil, "cookie domain hash verified before import")
            let firefoxJSON = try JSONSerialization.data(withJSONObject: ["windows": [["tabs": [["index": 1, "pinned": true, "entries": [["url": "https://firefox.example", "title": "Firefox"]]]]]]])
            var compressed = [UInt8](repeating: 0, count: firefoxJSON.count * 2 + 128)
            let capacity = compressed.count
            let length = firefoxJSON.withUnsafeBytes { source in
                compression_encode_buffer(&compressed, capacity, source.bindMemory(to: UInt8.self).baseAddress!, firefoxJSON.count, nil, COMPRESSION_LZ4_RAW)
            }
            var firefox = Data("mozLz40\0".utf8)
            var size = UInt32(firefoxJSON.count).littleEndian
            withUnsafeBytes(of: &size) { firefox.append(contentsOf: $0) }
            firefox.append(contentsOf: compressed.prefix(length))
            let firefoxFile = root.appending(path: "sessionstore.jsonlz4")
            try firefox.write(to: firefoxFile)
            let session = try ImportFileParser.read(firefoxFile)
            check(session.tabs.first?.url == "https://firefox.example" && session.tabs.first?.pinned == true, "Firefox compressed session imports current tab and pins")
            let snss = sessionFixture()
            let chromeTabs = try ChromiumSessionParser.read(snss)
            check(chromeTabs.count == 1 && chromeTabs.first?.url == "https://selected.example" && chromeTabs.first?.pinned == true, "Chromium session selects current navigation and omits closed tabs")
            var encryptedSession = Data("SNSS".utf8); append32(5, to: &encryptedSession)
            do { _ = try ChromiumSessionParser.read(encryptedSession); check(false, "encrypted session rejected clearly") }
            catch { check(error.localizedDescription.contains("encrypted"), "encrypted session rejected clearly") }
            let profile = root.appending(path: "Profile")
            try FileManager.default.createDirectory(at: profile.appending(path: "Sessions"), withIntermediateDirectories: true)
            try snss.write(to: profile.appending(path: "Sessions/Session_123"))
            try Data("{\"roots\":{\"bookmark_bar\":{\"children\":[{\"name\":\"Example\",\"url\":\"https://example.com\",\"type\":\"url\"}]}}}".utf8).write(to: profile.appending(path: "Bookmarks"))
            try database(profile.appending(path: "History"), sql: "CREATE TABLE urls(url TEXT,title TEXT,last_visit_time INTEGER); INSERT INTO urls VALUES('https://history.example','Visit',13344473600000000);")
            try database(profile.appending(path: "Cookies"), sql: "CREATE TABLE cookies(host_key TEXT,name TEXT,value TEXT,encrypted_value BLOB,path TEXT,expires_utc INTEGER,is_secure INTEGER,is_httponly INTEGER); CREATE TABLE meta(key TEXT,value TEXT); INSERT INTO meta VALUES('version','24'); INSERT INTO cookies VALUES('.example.com','test','plain',X'','/',0,1,1); INSERT INTO cookies VALUES('.example.com','encrypted','',X'763130','/',0,1,1);")
            let data = try await Task.detached { try BrowserProfileImporter.read(profile, kind: .chromium, decryptWith: nil) }.value
            check(data.bookmarks.count == 1 && data.history.count == 1 && data.tabs.count == 1 && data.cookies.count == 1, "Chromium profile imports bookmarks history sessions and plaintext cookies")
            check(data.notes.contains { $0.contains("encrypted cookies were skipped") }, "skipped encrypted cookies are reported without Keychain access")
            let state = BrowserState(store: SessionStore(directory: root.appending(path: "Destination")))
            let before = state.activeSpaceID
            var selection = ImportSelection(); selection.cookies = false
            _ = await state.applyImport(parsed, selection: selection, to: before)
            _ = await state.applyImport(parsed, selection: selection, to: before)
            check(state.tabs.count == 1 && state.folders.count == 1, "repeated session import preserves data and deduplicates tabs")
            let cookieStore = WebProfiles.dataStore(for: state.activeSpace.profileID).httpCookieStore
            let unselected = await cookieStore.allCookies()
            check(!unselected.contains { $0.name == "session" && $0.domain.contains("example.com") }, "cookie import requires explicit selection")
            selection.cookies = true
            _ = await state.applyImport(parsed, selection: selection, to: before)
            let imported = await cookieStore.allCookies()
            check(imported.contains { $0.name == "session" && $0.isHTTPOnly && $0.isSecure }, "selected cookies reach the destination WebKit store with security flags")
        } catch { check(false, "import fixture: \(error.localizedDescription)") }
        await OneClickImportChecks.run()
        await ChromiumGroupImportChecks.run()
        await BrowserImportAccessChecks.run()
        print("IKTEST importchecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }

    static func database(_ url: URL, sql: String) throws {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw CocoaError(.fileWriteUnknown) }
        defer { sqlite3_close(db) }
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw CocoaError(.fileWriteUnknown) }
    }

    private static func append32(_ value: Int, to data: inout Data) {
        var little = Int32(value).littleEndian
        withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
    }

    static func sessionFixture() -> Data {
        var data = Data("SNSS".utf8); append32(3, to: &data)
        func command(_ id: UInt8, _ payload: Data) {
            var size = UInt16(payload.count + 1).littleEndian
            withUnsafeBytes(of: &size) { data.append(contentsOf: $0) }
            data.append(id); data.append(payload)
        }
        func nav(_ tab: Int, _ index: Int, _ url: String) {
            var contents = Data(); append32(tab, to: &contents); append32(index, to: &contents)
            append32(url.utf8.count, to: &contents); contents.append(contentsOf: url.utf8)
            while contents.count % 4 != 0 { contents.append(0) }
            append32(0, to: &contents)
            var payload = Data(); append32(contents.count, to: &payload); payload.append(contents)
            command(6, payload)
        }
        nav(1, 0, "https://old.example"); nav(1, 1, "https://selected.example"); nav(2, 0, "https://closed.example")
        var selected = Data(); append32(1, to: &selected); append32(1, to: &selected); command(7, selected)
        var pin = Data(); append32(1, to: &pin); pin.append(1); command(12, pin)
        var close = Data(); append32(2, to: &close); command(16, close)
        return data
    }
}
#endif
