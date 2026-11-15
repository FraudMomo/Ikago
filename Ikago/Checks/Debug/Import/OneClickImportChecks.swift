#if DEBUG
import Foundation

private actor ImportReadTracker {
    private var sources: [DetectedBrowserProfile] = []
    func record(_ source: DetectedBrowserProfile) { sources.append(source) }
    func all() -> [DetectedBrowserProfile] { sources }
}

@MainActor
enum OneClickImportChecks {
    static func run() async {
        var failures = 0
        func check(_ value: Bool, _ title: String) {
            print("IKTEST oneclick \(value ? "PASS" : "FAIL") \(title)")
            if !value { failures += 1 }
        }
        let home = FileManager.default.temporaryDirectory.appending(path: "IkagoDiscovery-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        do {
            try fixture(home: home)
            let tracker = ImportReadTracker()
            let state = BrowserState(store: SessionStore(directory: home.appending(path: "Destination")))
            let original = state.activeSpaceID
            let target = state.createSpace(name: "Imported", symbol: "tray", isolated: true)
            let model = BrowserImportModel(home: home, reader: { source in
                await tracker.record(source)
                let data = try await Task.detached {
                    try BrowserProfileImporter.read(source.directory, kind: source.kind, decryptWith: nil)
                }.value
                // Switching Spaces while the read is running must not redirect imported logins.
                await state.switchSpace(original)
                return data
            })
            await model.refresh()
            let before = await tracker.all()
            check(before.isEmpty, "discovery reads no browsing records and requests no Keychain access")
            let chrome = model.profiles.filter { $0.browser == "Google Chrome" }
            check(chrome.count == 2 && chrome.first?.name == "Work" && chrome.first?.preferred == true,
                  "Chrome profiles detected and most recent profile listed first")
            check(chrome.allSatisfy { $0.kind == .chromium && $0.cookieKey == .chrome }, "source format and cookie key selected automatically")
            let firefox = model.profiles.filter { $0.browser == "Firefox" }
            check(firefox.count == 2 && firefox.first?.name == "Work Firefox", "Firefox named and absolute-path profiles detected with install default")
            check(model.profiles.contains { $0.browser == "Safari" }, "Safari source detected without choosing a folder")
            check(!model.profiles.contains { $0.directory.lastPathComponent == "Other" }, "Chromium metadata cannot traverse outside its profile root")
            let hidden = home.appending(path: "InaccessibleHome")
            let fallback = BrowserProfileDiscovery.discover(home: hidden, installedBrowsers: ["Google Chrome"])
            check(fallback.count == 1 && fallback.first?.browser == "Google Chrome" && fallback.first?.directory.lastPathComponent == "Default",
                  "installed Chrome stays selectable when profile metadata is inaccessible")
            let metadataHome = home.appending(path: "MetadataOnly")
            let metadataRoot = metadataHome.appending(path: "Library/Application Support/Google/Chrome")
            try FileManager.default.createDirectory(at: metadataRoot, withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: ["profile": ["info_cache": ["Profile 3": ["name": "Protected profile"]]]])
                .write(to: metadataRoot.appending(path: "Local State"))
            check(BrowserProfileDiscovery.discover(home: metadataHome).first?.name == "Protected profile",
                  "Chrome discovery does not require access to browsing databases")
            guard let source = chrome.first else { throw ImportFileParser.error("Missing fixture profile") }
            await model.importProfile(source, into: state)
            check(!model.failed && model.completed.contains(source.id) && model.importingID == nil,
                  "one Import action completes without preview or configuration")
            let reads = await tracker.all()
            check(reads.count == 1 && reads.first?.directory == source.directory && reads.first?.cookieKey == .chrome,
                  "only the clicked source is read with its matching cookie key")
            check(state.bookmarks.contains { $0.url == "https://work.example" } && !state.bookmarks.contains { $0.url == "https://personal.example" },
                  "one click imports selected browser bookmarks")
            check(state.tabs.count == 1 && state.tabs.first?.spaceID == target.id && state.tabs.first?.pinned == true,
                  "open tabs and pins go to the Space captured at click time")
            let imported = await WebProfiles.dataStore(for: target.profileID).httpCookieStore.allCookies()
            let personal = await WebProfiles.dataStore(for: "Default").httpCookieStore.allCookies()
            check(imported.contains { $0.name == "oneclick-session" && $0.isHTTPOnly && $0.isSecure },
                  "one click includes available logins without another checkbox")
            check(!personal.contains { $0.name == "oneclick-session" }, "imported logins stay in the chosen Space after navigation")
            let failing = BrowserImportModel(home: home, reader: { _ in throw CocoaError(.fileReadNoPermission) })
            await failing.importProfile(source, into: state)
            check(failing.failed && failing.importingID == nil && !failing.completed.contains(source.id),
                  "access failure is reported and the Import button can retry")
        } catch { check(false, error.localizedDescription) }
        print("IKTEST oneclickchecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }

    static func fixture(home: URL) throws {
        let support = home.appending(path: "Library/Application Support")
        let chrome = support.appending(path: "Google/Chrome")
        let personal = chrome.appending(path: "Default")
        let work = chrome.appending(path: "Profile 2")
        let firefox = support.appending(path: "Firefox")
        let personalFirefox = firefox.appending(path: "Profiles/abc.default-release")
        let externalFirefox = home.appending(path: "ExternalFirefox")
        for path in [personal, work.appending(path: "Sessions"), personalFirefox, externalFirefox, home.appending(path: "Library/Safari")] {
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        }
        let localState: [String: Any] = ["profile": ["last_used": "Profile 2", "info_cache": [
            "Default": ["name": "Personal"], "Profile 2": ["name": "Work"], "../Other": ["name": "Do not follow"]
        ]]]
        try JSONSerialization.data(withJSONObject: localState).write(to: chrome.appending(path: "Local State"))
        for (directory, address) in [(personal, "https://personal.example"), (work, "https://work.example")] {
            let bookmarks: [String: Any] = ["roots": ["bookmark_bar": ["children": [["name": "Example", "url": address, "type": "url"]]]]]
            try JSONSerialization.data(withJSONObject: bookmarks).write(to: directory.appending(path: "Bookmarks"))
        }
        try BrowserImportChecks.sessionFixture().write(to: work.appending(path: "Sessions/Session_123"))
        if !FileManager.default.fileExists(atPath: work.appending(path: "Cookies").path) {
            try BrowserImportChecks.database(work.appending(path: "Cookies"), sql: "CREATE TABLE cookies(host_key TEXT,name TEXT,value TEXT,encrypted_value BLOB,path TEXT,expires_utc INTEGER,is_secure INTEGER,is_httponly INTEGER); CREATE TABLE meta(key TEXT,value TEXT); INSERT INTO meta VALUES('version','24'); INSERT INTO cookies VALUES('.example.org','oneclick-session','fixture',X'','/',0,1,1);")
        }
        try Data().write(to: personalFirefox.appending(path: "places.sqlite"))
        try Data().write(to: externalFirefox.appending(path: "places.sqlite"))
        let ini = """
            [Profile0]
            Name=Personal Firefox
            IsRelative=1
            Path=Profiles/abc.default-release
            Default=1
            [Profile1]
            Name=Work Firefox
            IsRelative=0
            Path=\(externalFirefox.path)
            [InstallTEST]
            Default=\(externalFirefox.path)
            Locked=1
            """
        try Data(ini.utf8).write(to: firefox.appending(path: "profiles.ini"))
    }
}
#endif
