#if DEBUG
import Foundation

/// Remove Chromium: only Chromium's folders go (never the rest of Ikago's data), WebKit becomes the engine for everything,
/// and nothing is deleted while Chromium runs. Works in a temporary data folder.
@MainActor
enum ChromiumRemovalChecks {
    static func run() async {
        var failures = 0
        func check(_ value: Bool, _ title: String) {
            print("IKTEST chromiumremoval \(value ? "PASS" : "FAIL") \(title)")
            if !value { failures += 1 }
        }
        let root = FileManager.default.temporaryDirectory.appending(path: "IkagoChromiumRemoval-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let files = FileManager.default
        func make(_ path: String) {
            let url = root.appending(path: path)
            try? files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data(repeating: 7, count: 64_000).write(to: url)
        }
        for path in ["Chromium/Default/Cookies", "Chromium Extensions/abc/manifest.json", "CEF/Profiles/old", "WebKit/keep", "session.json", "passwords.vault"] {
            make(path)
        }
        let state = BrowserState(store: SessionStore(directory: root.appending(path: "session")))
        state.browserPreferences.preferredEngine = .chromium
        state.browserPreferences.siteEngines = ["example.com": BrowserEngine.chromium.rawValue, "apple.com": BrowserEngine.webkit.rawValue]
        state.browserPreferences.siteEngineLists = ["streaming": BrowserEngine.chromium.rawValue]

        check(await ChromiumRemoval.size(in: root) >= 3 * 64_000, "Chromium's data is measured")
        check(ChromiumRemoval.remove(state: state, running: true, root: root) == false
              && ChromiumRemoval.hasData(in: root), "while Chromium runs nothing is deleted (it waits for a launch without it)")
        check(state.browserPreferences.preferredEngine == .webkit, "WebKit becomes the engine")
        check(state.browserPreferences.siteEngines == ["apple.com": BrowserEngine.webkit.rawValue]
              && state.browserPreferences.siteEngineLists?.isEmpty == true, "sites set to Chromium go back to WebKit; others keep theirs")

        check(ChromiumRemoval.remove(state: state, running: false, root: root), "without Chromium running it is removed at once")
        check(!ChromiumRemoval.hasData(in: root), "Chromium's profiles, extensions and old folder are gone")
        check(["WebKit/keep", "session.json", "passwords.vault"].allSatisfy { files.fileExists(atPath: root.appending(path: $0).path) },
              "the rest of Ikago's data stays")
        print("IKTEST chromiumremovalchecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }
}
#endif
