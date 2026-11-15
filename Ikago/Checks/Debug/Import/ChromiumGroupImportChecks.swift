#if DEBUG
import Foundation

@MainActor
enum ChromiumGroupImportChecks {
    static func run() async {
        var failures = 0
        func check(_ value: Bool, _ title: String) {
            print("IKTEST tabgroups \(value ? "PASS" : "FAIL") \(title)")
            if !value { failures += 1 }
        }
        let root = FileManager.default.temporaryDirectory.appending(path: "IkagoGroupChecks-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            let profile = root.appending(path: "Chrome/Default"), sessions = profile.appending(path: "Sessions")
            try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
            try ChromiumGroupFixture.grouped().write(to: sessions.appending(path: "Session_100"))
            let imported = try BrowserProfileImporter.read(profile, kind: .chromium, decryptWith: nil)
            let tabs = imported.tabs
            check(tabs.count == 8 && !tabs.contains { $0.url.hasSuffix("/7") || $0.url.hasSuffix("/8") },
                  "closed tabs and closed windows do not resurrect group members")
            let purple = tabs.first { $0.groupColor == "purple" }, orange = tabs.first { $0.groupColor == "orange" }
            check(purple?.group == "Research 🧭" && purple?.groupCollapsed == true,
                  "latest UTF-16 group title, color and collapsed state win")
            check(purple?.group == orange?.group && purple?.groupID != orange?.groupID,
                  "same-named Chrome groups keep distinct token identities")
            check(tabs.first { $0.url.hasSuffix("/5") }?.groupID == nil && tabs.first { $0.url.hasSuffix("/6") }?.groupID == orange?.groupID,
                  "ungroup and reassignment commands update membership")
            check(tabs.first { $0.url.hasSuffix("/9") }?.pinned == true && tabs.first { $0.url.hasSuffix("/9") }?.groupID == nil,
                  "pinned tabs remain pinned outside folders")
            check(tabs.first { $0.url.hasSuffix("/4") }?.group == "Imported Group" && tabs.first { $0.url.hasSuffix("/4") }?.groupColor == "gray",
                  "unnamed groups and unknown colors have readable fallbacks")
            check(tabs.first { $0.url.hasSuffix("/10") }?.groupID != nil, "membership survives absent visual metadata")
            check(imported.notes.contains { $0.contains("become Ikago folders") }, "import details describe group conversion")
            try ChromiumGroupFixture.grouped().write(to: sessions.appending(path: "Session_200"))
            let newer = try BrowserProfileImporter.read(profile, kind: .chromium, decryptWith: nil)
            check(newer.tabs.map(\.groupID) == tabs.map(\.groupID), "group identity survives a new session filename")
            let other = try ChromiumSessionParser.read(ChromiumGroupFixture.grouped(), groupNamespace: "Other profile")
            check(other.first?.groupID != tabs.first?.groupID, "group identities are scoped to their source profile")
            let store = SessionStore(directory: root.appending(path: "Destination"))
            let state = BrowserState(store: store), spaceID = state.activeSpaceID
            let original = state.newTab(url: "https://groups.example/1")!
            let unrelated = state.createFolder(named: "Research 🧭")
            let summary = await state.applyImport(imported, selection: ImportSelection(), to: spaceID)
            let grouped = state.spaceFolders.filter { $0.id != unrelated.id }
            check(grouped.count == 4 && summary.contains("4 groups"), "only groups with imported live tabs become folders")
            let purpleFolder = grouped.first { $0.tag == "purple" }, orangeFolder = grouped.first { $0.tag == "orange" }
            check(purpleFolder?.name == "Research 🧭" && purpleFolder?.isOpen == false && orangeFolder?.isOpen == true,
                  "folders retain names, colors and collapsed state")
            check(purpleFolder.map { state.tabs(in: $0).count } == 2 && orangeFolder.map { state.tabs(in: $0).count } == 2,
                  "tab membership is retained even when two groups contain the same URL")
            check(state.tab(original.id)?.folderID == nil && state.folders.contains(unrelated), "existing tabs and same-named folders stay untouched")
            let before = state.snapshot()
            _ = await state.applyImport(imported, selection: ImportSelection(), to: spaceID)
            check(state.snapshot().tabs == before.tabs && state.folders == before.folders, "reimport creates no duplicate tabs or folders")
            if let purpleFolder {
                state.renameFolder(purpleFolder.id, to: "My research")
                state.setFolderTag(purpleFolder.id, to: .green)
                state.toggleFolder(purpleFolder.id)
                var addition = imported
                var tab = purple!; tab.url = "https://groups.example/new"; addition.tabs.append(tab)
                _ = await state.applyImport(addition, selection: ImportSelection(), to: spaceID)
                check(state.tabs(in: state.folders.first { $0.id == purpleFolder.id }!).count == 3 && state.folders.count == 5,
                      "later imports add new members to the existing imported folder")
                let edited = state.folders.first { $0.id == purpleFolder.id }
                check(edited?.name == "My research" && edited?.tag == "green" && edited?.isOpen == true,
                      "reimport preserves user edits to folder name, color and expansion")
            }
            state.saveNow()
            let restored = BrowserState(store: store)
            check(restored.folders == state.folders && restored.tabs.map(\.saved) == state.tabs.map(\.saved),
                  "imported folder metadata and memberships survive session restore")
            let second = state.createSpace(name: "Other", symbol: "star", isolated: false)
            _ = await state.applyImport(imported, selection: ImportSelection(), to: second.id)
            check(state.spaceFolders.count == 4 && Set(state.spaceFolders.map(\.id)).isDisjoint(with: Set(grouped.map(\.id))),
                  "importing into another Space keeps its own folder identities")
            let oneClickState = BrowserState(store: SessionStore(directory: root.appending(path: "OneClick")))
            let source = DetectedBrowserProfile(browser: "Google Chrome", name: "Fixture", directory: profile, kind: .chromium, cookieKey: nil)
            let model = BrowserImportModel(home: root, reader: { source in
                try BrowserProfileImporter.read(source.directory, kind: source.kind, decryptWith: nil)
            })
            await model.importProfile(source, into: oneClickState)
            check(!model.failed && oneClickState.folders.count == 4 && model.result?.contains("4 groups") == true,
                  "one-click browser import includes group conversion without extra configuration")
            let full = BrowserState(store: SessionStore(directory: root.appending(path: "Full")))
            full.tabs = (0..<Session.maxTabs).map { TabItem(url: "https://full.example/\($0)", spaceID: full.activeSpaceID) }
            let limitedSummary = await full.applyImport(imported, selection: ImportSelection(), to: full.activeSpaceID)
            check(full.folders.isEmpty && full.tabs.count == Session.maxTabs && limitedSummary.contains("limit was reached"),
                  "tab limit is reported without empty folders or replacing existing tabs")
            let expected = ["gray", "blue", "red", "yellow", "green", "pink", "purple", "teal", "orange"]
            var colors = ChromiumGroupFixture()
            for color in 0..<9 {
                colors.nav(color + 1, url: "https://colors.example/\(color)")
                colors.member(color + 1, group: UInt64(color + 1), abi32: true)
                colors.metadata(UInt64(color + 1), title: "Color \(color)", color: color)
            }
            check(try ChromiumSessionParser.read(colors.data).map(\.groupColor) == expected,
                  "all nine Chrome colors map to folder tags, including cyan to teal and 32-bit records")
            var legacy = ChromiumGroupFixture()
            legacy.nav(1, url: "https://legacy.example"); legacy.member(1, group: 1)
            legacy.metadata(1, title: "Legacy", color: -1, collapsed: nil, legacy: true)
            let old = try ChromiumSessionParser.read(legacy.data).first
            check(old?.group == "Legacy" && old?.groupColor == "gray" && old?.groupCollapsed == false,
                  "legacy group metadata preserves title with a safe color fallback")
            var preCollapsed = ChromiumGroupFixture()
            preCollapsed.nav(1, url: "https://old.example"); preCollapsed.member(1, group: 1)
            var body = ChromiumGroupFixture.u64(0x1122334455667788) + ChromiumGroupFixture.u64(1)
            body += ChromiumGroupFixture.u32(0) + ChromiumGroupFixture.u32(1)
            preCollapsed.command(27, ChromiumGroupFixture.u32(body.count) + body)
            check(try ChromiumSessionParser.read(preCollapsed.data).first?.groupCollapsed == false, "pre-M88 metadata without collapsed state remains supported")
            var malformed = ChromiumGroupFixture(); malformed.command(25, Data(repeating: 0, count: 10))
            do { _ = try ChromiumSessionParser.read(malformed.data); check(false, "unsupported membership rejected") }
            catch { check(error.localizedDescription.contains("tab-group"), "unsupported membership rejected clearly") }
            var damaged = ChromiumGroupFixture(); damaged.command(27, Data(repeating: 0xff, count: 28))
            do { _ = try ChromiumSessionParser.read(damaged.data); check(false, "damaged metadata rejected") }
            catch { check(error.localizedDescription.contains("tab-group"), "damaged metadata rejected clearly") }
            var truncated = ChromiumGroupFixture.grouped(); truncated.removeLast()
            do { _ = try ChromiumSessionParser.read(truncated); check(false, "truncated session rejected") }
            catch { check(error.localizedDescription.contains("truncated"), "truncated session rejected clearly") }
        } catch { check(false, "group fixture: \(error.localizedDescription)") }
        print("IKTEST tabgroupchecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }
}
#endif
