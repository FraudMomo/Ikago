#if DEBUG
import Foundation

/// Export and import without anyone at the keyboard: every format Ikago writes reads back the same (bookmarks with their
/// folders, history, passwords), its ZIP passes `unzip -t`, archives other tools write (deflated) read too, importing
/// twice adds nothing, and the report says what happened to each kind of data. Uses a temporary vault and session.
@MainActor
enum ImportExportChecks {
    static func run() async {
        var failures = 0
        func check(_ value: Bool, _ title: String) {
            print("IKTEST importexport \(value ? "PASS" : "FAIL") \(title)")
            if !value { failures += 1 }
        }
        let root = FileManager.default.temporaryDirectory.appending(path: "IkagoImportExport-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // A library with the awkward cases: nesting, markup characters, accents and emoji, a non-web address.
        let work = BookmarkFolder(name: "Work & <Play>")
        let projects = BookmarkFolder(name: "Projects \"2026\"", parentID: work.id)
        let reading = BookmarkFolder(name: "Läsning 📚")
        let bookmarks = [
            Bookmark(url: "https://example.com/a?x=1&y=2", title: "Top & <level>"),
            Bookmark(url: "https://example.org/work", title: "Work's \"page\"", folderID: work.id),
            Bookmark(url: "https://example.net/deep", title: "Deep — é ü 🚀", folderID: projects.id),
            Bookmark(url: "https://example.com/read", title: "", folderID: reading.id),
            Bookmark(url: "javascript:alert(1)", title: "Script", folderID: reading.id),
        ]
        let folders = [work, projects, reading]
        let history = [
            Visit(url: "https://example.com/a", title: "A & B", time: 1_763_000_000_000, visits: 4, typed: 1),
            Visit(url: "https://example.org/b", title: "", time: 1_762_000_000_000, visits: 1, typed: 0),
        ]
        let passwords = [
            BrowserExport.Password(title: "Example", url: "https://example.com", username: "me@example.com", password: "p\"a,s\ns"),
            BrowserExport.Password(title: "Other", url: "https://login.example.org", username: "", password: "secret"),
        ]

        // Bookmarks HTML.
        let html = BrowserExport.bookmarksHTML(bookmarks, folders: folders)
        let htmlFile = root.appending(path: "Bookmarks.html")
        try? Data(html.utf8).write(to: htmlFile)
        let readHTML = (try? ImportFileParser.read(htmlFile))?.bookmarks ?? []
        func key(_ url: String, _ title: String, _ path: [String]) -> String { "\(url)|\(title)|\(path.joined(separator: "/"))" }
        let expected: Set<String> = [
            key("https://example.com/a?x=1&y=2", "Top & <level>", ["Bookmarks Bar"]),
            key("https://example.org/work", "Work's \"page\"", ["Bookmarks Bar", "Work & <Play>"]),
            key("https://example.net/deep", "Deep — é ü 🚀", ["Bookmarks Bar", "Work & <Play>", "Projects \"2026\""]),
            key("https://example.com/read", "https://example.com/read", ["Bookmarks Bar", "Läsning 📚"]),
        ]
        check(Set(readHTML.map { key($0.url, $0.title, $0.folders) }) == expected, "bookmarks HTML reads back with titles and folders")
        check(html.hasPrefix("<!DOCTYPE NETSCAPE-Bookmark-file-1>") && html.contains("PERSONAL_TOOLBAR_FOLDER=\"true\""),
              "bookmarks HTML is the Netscape format, the top level marked as the toolbar")
        check(!html.contains("javascript:"), "non-web bookmarks are left out")

        // History JSON in Safari's format.
        let historyJSON = BrowserExport.historyJSON(history)
        check(historyJSON.hasPrefix("{\"metadata\":") && historyJSON.contains("\"data_type\":\"history\""),
              "history JSON starts with Safari's metadata (Chrome needs it first)")
        let historyFile = root.appending(path: "History.json")
        try? Data(historyJSON.utf8).write(to: historyFile)
        let readHistory = (try? ImportFileParser.read(historyFile))?.history ?? []
        check(readHistory.count == 2 && readHistory.first { $0.url == "https://example.com/a" }.map { $0.time == 1_763_000_000_000 && $0.visits == 4 && $0.title == "A & B" } == true,
              "history reads back with times, visit counts and titles")
        check(readHistory.first { $0.url == "https://example.org/b" }?.title == "https://example.org/b", "an untitled page reads back titled by its address")

        // Passwords CSV.
        let csv = BrowserExport.passwordsCSV(passwords)
        let parsed = try? PasswordImport.parse(csv)
        check(parsed?.logins.count == 2 && parsed?.logins.first?.password == "p\"a,s\ns" && parsed?.logins.first?.username == "me@example.com",
              "passwords with quotes, commas and line breaks read back")

        // The archive: written stored, checked by unzip, read back by Ikago.
        let archive = BrowserExport.archive(bookmarks: html, history: historyJSON, passwords: csv)
        let zipFile = root.appending(path: "Ikago Export.zip")
        try? BrowserExport.save(archive, to: zipFile)
        let entries = (try? ZipArchive.read(archive)) ?? []
        check(entries.map(\.name) == ["Bookmarks.html", "History.json", "Passwords.csv"] && entries.first?.data == Data(html.utf8),
              "the archive holds Safari's three files, byte for byte")
        check(run("/usr/bin/unzip", ["-tq", zipFile.path]) == 0, "unzip -t accepts Ikago's archive")
        let permissions = (try? FileManager.default.attributesOfItem(atPath: zipFile.path)[.posixPermissions] as? Int) ?? 0
        check(permissions == 0o600, "the export is readable by its owner only")
        let readZip = try? ImportFileParser.read(zipFile)
        check(readZip?.bookmarks.count == 4 && readZip?.history.count == 2 && readZip?.passwords.count == 2,
              "the archive imports bookmarks, history and passwords")

        // Archives other tools write: deflated, with folders and macOS's resource forks, and parts Ikago doesn't use.
        let source = root.appending(path: "source")
        try? FileManager.default.createDirectory(at: source.appending(path: "Safari Export"), withIntermediateDirectories: true)
        try? Data((html + String(repeating: "<!-- padding so it deflates -->\n", count: 200)).utf8).write(to: source.appending(path: "Safari Export/Bookmarks.html"))
        try? Data(historyJSON.utf8).write(to: source.appending(path: "Safari Export/History.json"))
        try? Data(#"{"metadata":{"data_type":"payment_cards"},"payment_cards":[{"card_number":"4111111111111111"}]}"#.utf8)
            .write(to: source.appending(path: "Safari Export/PaymentCards.json"))
        let deflated = root.appending(path: "deflated.zip")
        let zipped = run("/usr/bin/zip", ["-qr", deflated.path, "Safari Export"], in: source)
        let readDeflated = zipped == 0 ? try? ImportFileParser.read(deflated) : nil
        check(zipped == 0 && readDeflated?.bookmarks.count == 4 && readDeflated?.history.count == 2 && readDeflated?.passwords.isEmpty == true,
              "a deflated archive from zip reads, skipping parts Ikago doesn't use")
        check((try? ZipArchive.read(Data("not a zip".utf8))) == nil && (try? ZipArchive.read(archive.prefix(archive.count - 10))) == nil,
              "damaged archives are refused, not misread")

        // Chrome's data portability history, and entities in other browsers' bookmark files.
        let portability = #"{"metadata":{"data_type":"history_visits"},"history_visits":[{"title":"P","url":"https://example.com/p","visit_time_unix_epoch_usec":1700000000000000,"visit_count":3,"typed_count":2}]}"#
        let portabilityFile = root.appending(path: "Portability.json")
        try? Data(portability.utf8).write(to: portabilityFile)
        let readPortability = (try? ImportFileParser.read(portabilityFile))?.history.first
        check(readPortability?.time == 1_700_000_000_000 && readPortability?.visits == 3 && readPortability?.typed == 2,
              "Chrome's data portability history reads with its counts")
        check(ImportFileParser.entities("Caf&#233; &#x27;x&#x27; &amp;lt; &apos;") == "Café 'x' &lt; '", "numeric and named entities decode once")

        // Applying: everything comes in, a second time nothing does, and the report says why.
        let state = BrowserState(store: SessionStore(directory: root.appending(path: "session")))
        let vault = PasswordVault(directory: root.appending(path: "vault"), usesTestKey: true)
        guard let data = readZip else { check(false, "the archive parsed"); return finish(failures) }
        let first = await state.applyImport(data, selection: ImportSelection(), to: state.activeSpaceID, passwordVault: vault)
        func item(_ report: ImportReport, _ kind: String) -> ImportReport.Item? { report.items.first { $0.kind == kind } }
        check(item(first, "Bookmarks")?.imported == 4 && item(first, "History")?.imported == 2 && item(first, "Passwords")?.imported == 2,
              "a first import brings in every bookmark, page and password")
        check(state.bookmarkFolders.contains { $0.name == "Projects \"2026\"" } && state.bookmarks.count == 4, "bookmarks keep their folders")
        let restoredWork = state.bookmarkFolders.first { $0.name == "Work & <Play>" }
        check(restoredWork?.parentID == nil && state.bookmarks.first { $0.url == "https://example.com/a?x=1&y=2" }?.folderID == nil
              && !state.bookmarkFolders.contains { $0.name.hasPrefix("Imported") },
              "Ikago's own export restores the Bookmarks Bar and its folders as they were")
        let second = await state.applyImport(data, selection: ImportSelection(), to: state.activeSpaceID, passwordVault: vault)
        check(item(second, "Bookmarks")?.imported == 0 && item(second, "History")?.imported == 0 && item(second, "Passwords")?.imported == 0
              && state.bookmarks.count == 4 && vault.logins.count == 2, "importing again adds nothing")
        check(item(second, "Bookmarks")?.details == ["4 already in Ikago"] && item(second, "Passwords")?.details == ["2 already saved"]
              && item(second, "History")?.summary == "0 of 2 imported · 2 already in your history",
              "the report says why each was skipped")

        // Another browser's bar: bookmarks already on Ikago's Bookmarks Bar stay there, deeper ones keep their folders.
        let mine = BrowserState(store: SessionStore(directory: root.appending(path: "mine")))
        mine.bookmarks = [Bookmark(url: "https://example.com/a?x=1&y=2", title: "Mine")]
        let foreign = (try? ImportFileParser.read(htmlFile)).map { data -> BrowserImportData in
            var data = data; data.fromIkago = false; data.sourceName = "Chrome"; return data
        }
        if let foreign {
            let report = await mine.applyImport(foreign, selection: ImportSelection(), to: mine.activeSpaceID, passwordVault: vault)
            check(mine.bookmarks.first { $0.title == "Mine" }?.folderID == nil && item(report, "Bookmarks")?.details.contains("1 already in Ikago") == true,
                  "importing never moves your own Bookmarks Bar into an Imported folder")
            check(mine.bookmarkFolders.contains { $0.name == "Imported from Chrome" } && mine.bookmarks.count == 4,
                  "another browser's bookmarks arrive in their Imported folder")
        }
        print("IKTEST importexportchecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }

    private static func finish(_ failures: Int) {
        print("IKTEST importexportchecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }

    /// Runs a system tool and returns its exit status (-1 when it couldn't start).
    private static func run(_ tool: String, _ arguments: [String], in directory: URL? = nil) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        if let directory { process.currentDirectoryURL = directory }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return -1 }
        process.waitUntilExit()
        return process.terminationStatus
    }
}
#endif
