#if DEBUG
import Foundation

private actor AccessReadTracker {
    var reads = 0
    func record() { reads += 1 }
    func count() -> Int { reads }
}

@MainActor
enum BrowserImportAccessChecks {
    static func run() async {
        var failures = 0
        func check(_ value: Bool, _ title: String) {
            print("IKTEST importaccess \(value ? "PASS" : "FAIL") \(title)")
            if !value { failures += 1 }
        }
        let root = FileManager.default.temporaryDirectory.appending(path: "IkagoAccessChecks-\(UUID().uuidString)")
        let profile = root.appending(path: "Chrome/Default")
        let protected = ["Bookmarks", "History", "Cookies", "Sessions"]
        defer {
            for file in protected { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: profile.appending(path: file).path) }
            try? FileManager.default.removeItem(at: root)
        }
        do {
            let sessions = profile.appending(path: "Sessions")
            try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
            try Data("{\"roots\":{\"bookmark_bar\":{\"children\":[{\"name\":\"Allowed\",\"url\":\"https://allowed.example\",\"type\":\"url\"}]}}}".utf8)
                .write(to: profile.appending(path: "Bookmarks"))
            try ChromiumGroupFixture.grouped().write(to: sessions.appending(path: "Session_100"))
            try BrowserImportChecks.database(profile.appending(path: "History"), sql: "CREATE TABLE urls(url TEXT,title TEXT,last_visit_time INTEGER);")
            try BrowserImportChecks.database(profile.appending(path: "Cookies"), sql: "CREATE TABLE cookies(host_key TEXT,name TEXT,value TEXT,encrypted_value BLOB,path TEXT,expires_utc INTEGER,is_secure INTEGER,is_httponly INTEGER); CREATE TABLE meta(key TEXT,value TEXT);")
            let source = DetectedBrowserProfile(browser: "Google Chrome", name: "Fixture", directory: profile, kind: .chromium, cookieKey: nil)
            check(BrowserImportAccess.blockedResources(source).isEmpty, "readable profiles need no permission panel")
            for file in protected { try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: profile.appending(path: file).path) }
            let blocked = BrowserImportAccess.blockedResources(source)
            check(protected.allSatisfy(blocked.contains), "preflight detects denied bookmarks, databases and session directory")
            let denied = try BrowserProfileImporter.read(profile, kind: .chromium, decryptWith: nil)
            check(!denied.hasData && protected.allSatisfy(denied.accessIssues.contains), "importer preserves structured access failures rather than treating files as absent")
            let state = BrowserState(store: SessionStore(directory: root.appending(path: "Destination")))
            let original = state.newTab(url: "https://existing.example")!
            let tracker = AccessReadTracker()
            let cancelled = BrowserImportModel(home: root, accessPreparer: { _, _ in throw CancellationError() }, reader: { _ in
                await tracker.record(); return BrowserImportData()
            })
            await cancelled.importProfile(source, into: state)
            check(await tracker.count() == 0 && state.tabs.count == 1 && state.tab(original.id) != nil,
                  "cancelling permission approval reads no browser records and keeps existing data")
            check(cancelled.importingID == nil && cancelled.accessNeededFor?.id == source.id && cancelled.result?.contains("cancelled") == true,
                  "cancelled approval offers a retry without leaving import busy")
            var attempts: [Bool] = []
            let model = BrowserImportModel(home: root, accessPreparer: { source, force in
                attempts.append(force)
                if !force { throw CocoaError(.fileReadNoPermission) }
                // Test-only grant: restore this fixture's file modes, never touch real profile permissions.
                for file in protected { try FileManager.default.setAttributes([.posixPermissions: file == "Sessions" ? 0o700 : 0o600], ofItemAtPath: source.directory.appending(path: file).path) }
                return BrowserImportAccess.Grant(directory: source.directory)
            }, reader: { source in
                await tracker.record()
                return try BrowserProfileImporter.read(source.directory, kind: source.kind, decryptWith: nil)
            })
            await model.importProfile(source, into: state)
            check(model.failed && model.accessNeededFor?.id == source.id && !model.completed.contains(source.id),
                  "denied access exposes an actionable retry and does not claim completion")
            check(await tracker.count() == 0, "permission preparation happens before browsing or Keychain reads")
            await model.retryWithAccess(into: state)
            let readsAfterRetry = await tracker.count()
            check(attempts == [false, true] && readsAfterRetry == 1, "Allow Access and Retry forces approval then reads once")
            check(!model.failed && model.accessNeededFor == nil && model.completed.contains(source.id)
                  && state.bookmarks.contains { $0.url == "https://allowed.example" } && state.folders.count == 4,
                  "approved retry imports Chrome bookmarks, tabs and groups")
            let partial = BrowserImportModel(home: root, reader: { _ in
                BrowserImportData(bookmarks: [Bookmark(url: "https://partial.example", title: "Partial")], accessIssues: ["Cookies"])
            })
            await partial.importProfile(source, into: state)
            check(partial.failed && partial.accessNeededFor != nil && !partial.completed.contains(source.id) && partial.result?.contains("Some browser data is blocked") == true,
                  "partial import keeps available data and remains retryable for blocked records")
            let deniedFile = BrowserImportModel(home: root, reader: { _ in throw CocoaError(.fileReadNoPermission) })
            let fileSource = DetectedBrowserProfile(browser: "Export", name: "Fixture", directory: profile.appending(path: "Bookmarks"), kind: .file, cookieKey: nil)
            await deniedFile.importProfile(fileSource, into: state)
            check(deniedFile.failed && deniedFile.accessNeededFor == nil && deniedFile.result?.contains("Choose it again") == true,
                  "export-file failures do not offer an ineffective profile-folder retry")
            let missing = DetectedBrowserProfile(browser: "Chrome", name: "Missing", directory: root.appending(path: "Missing"), kind: .chromium, cookieKey: nil)
            check(BrowserImportAccess.blockedResources(missing).isEmpty, "missing profiles do not trigger a spurious permission prompt")
            let empty = try BrowserProfileImporter.read(missing.directory, kind: .chromium, decryptWith: nil)
            check(empty.accessIssues.isEmpty && !empty.hasData, "missing source files stay distinct from access denial")
            let corrupt = profile.appending(path: "Corrupt")
            try Data("not a database".utf8).write(to: corrupt)
            do { _ = try ImportDatabase(corrupt).rows("SELECT * FROM urls"); check(false, "corrupt database rejected") }
            catch { check(!ImportAccessError.isPermissionDenied(error), "corrupt databases are not mislabeled as permission errors") }
            check(ImportAccessError.isPermissionDenied(NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM)))
                  && ImportAccessError.isPermissionDenied(NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnknownError,
                    userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))])),
                  "POSIX and wrapped macOS privacy denials are recognized")
        } catch { check(false, error.localizedDescription) }
        print("IKTEST importaccesschecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }
}
#endif
