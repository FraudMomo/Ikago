#if DEBUG
import Foundation

/// macOS 14 and later hide other apps' data folders until the person allows each one. These checks stand in for that
/// with folder permissions on a fixture home (never a real profile): a hidden browser must show as one "allow access"
/// entry, not as a guessed empty profile, and allowing it must import the profile the browser actually uses.
@MainActor
enum BrowserDiscoveryAccessChecks {
    static func run() async {
        var failures = 0
        func check(_ value: Bool, _ title: String) {
            print("IKTEST discoveryaccess \(value ? "PASS" : "FAIL") \(title)")
            if !value { failures += 1 }
        }
        let home = FileManager.default.temporaryDirectory.appending(path: "IkagoDiscoveryChecks-\(UUID().uuidString)")
        let chrome = home.appending(path: "Library/Application Support/Google/Chrome")
        let safari = home.appending(path: "Library/Safari")
        let safariCookies = home.appending(path: "Library/Containers/com.apple.Safari/Data/Library/Cookies")
        func setMode(_ mode: Int, _ url: URL) { try? FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path) }
        defer {
            for folder in [chrome, safari, safariCookies] { setMode(0o700, folder) }
            setMode(0o600, safariCookies.appending(path: "Cookies.binarycookies"))
            try? FileManager.default.removeItem(at: home)
        }
        do {
            // Chrome's profile in use is "Profile 1"; "Default" doesn't exist.
            let work = chrome.appending(path: "Profile 1")
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            try Data(#"{"profile":{"last_used":"Profile 1","info_cache":{"Profile 1":{"name":"Work"}}}}"#.utf8).write(to: chrome.appending(path: "Local State"))
            try Data(#"{"roots":{"bookmark_bar":{"children":[{"name":"Work site","url":"https://work.example","type":"url"}]}}}"#.utf8)
                .write(to: work.appending(path: "Bookmarks"))
            try FileManager.default.createDirectory(at: safari, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: safariCookies, withIntermediateDirectories: true)
            try Data().write(to: safariCookies.appending(path: "Cookies.binarycookies"))

            let open = BrowserProfileDiscovery.discover(home: home)
            let visible = open.first { $0.browser == "Google Chrome" }
            check(visible?.name == "Work" && visible?.directory.lastPathComponent == "Profile 1" && visible?.accessRoot?.lastPathComponent == "Chrome"
                  && visible?.needsAccess == false, "a readable browser lists its real profile, with its data folder to allow")

            setMode(0, chrome)
            setMode(0, safari)
            let hidden = BrowserProfileDiscovery.discover(home: home, installedBrowsers: ["Google Chrome"])
            let chromeEntries = hidden.filter { $0.browser == "Google Chrome" }
            check(chromeEntries.count == 1 && chromeEntries[0].needsAccess && chromeEntries[0].directory.lastPathComponent == "Chrome",
                  "a hidden browser shows as one entry that asks for access")
            check(!hidden.contains { $0.name == "Default profile" }, "no guessed empty Default profile is listed")
            check(hidden.first { $0.browser == "Safari" }?.needsAccess == true, "a hidden Safari folder asks for access")
            check(chromeEntries.first?.subtitle.contains("Allow access") == true, "the entry says access is what is missing")

            // Allowing access opens the picker on Chrome's data folder, then imports the profile Chrome last used.
            var asked: [URL?] = []
            let state = BrowserState(store: SessionStore(directory: home.appending(path: "Destination")))
            let model = BrowserImportModel(home: home, accessPreparer: { source, _ in
                asked.append(source.accessRoot)
                setMode(0o700, chrome)  // the person clicked Allow Import
                return nil
            }, reader: { source in try BrowserProfileImporter.read(source.directory, kind: source.kind, decryptWith: nil) })
            await model.refresh()
            if let entry = model.profiles.first(where: { $0.browser == "Google Chrome" }) {
                await model.importProfile(entry, into: state)
            }
            check(asked.count == 1 && asked.first??.lastPathComponent == "Chrome", "the Allow picker opens on the browser's data folder")
            check(!model.failed && state.bookmarks.contains { $0.url == "https://work.example" },
                  "after allowing, the profile in use (Profile 1) is imported")
            check(model.profiles.contains { $0.browser == "Google Chrome" && $0.name == "Work" && !$0.needsAccess },
                  "after allowing, the list shows the real profile")

            // An installed browser that never ran has nothing to import and isn't listed.
            setMode(0o700, chrome)
            try FileManager.default.removeItem(at: chrome)
            try FileManager.default.createDirectory(at: chrome, withIntermediateDirectories: true)
            check(!BrowserProfileDiscovery.discover(home: home, installedBrowsers: ["Google Chrome"]).contains { $0.browser == "Google Chrome" },
                  "an installed browser without data isn't offered as an empty profile")

            // Safari's container (logins, open tabs) is the one place only Full Disk Access opens.
            setMode(0o700, safari)
            try Data().write(to: safari.appending(path: "History.db"))
            // macOS lets Ikago see the file exists but refuses to open it.
            setMode(0, safariCookies.appending(path: "Cookies.binarycookies"))
            let safariData = try BrowserProfileImporter.read(safari, kind: .safari, decryptWith: nil)
            check(safariData.needsFullDiskAccess, "blocked Safari logins ask for Full Disk Access")
        } catch { check(false, error.localizedDescription) }
        print("IKTEST discoveryaccesschecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }
}
#endif
