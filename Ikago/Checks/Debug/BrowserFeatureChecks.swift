#if DEBUG
import AppKit
import WebKit

/// End-to-end regression checks using only the isolated test profile and local fixtures.
@MainActor
enum BrowserFeatureChecks {
    static func run(_ browser: BrowserWindowController) async {
        var failures: [String] = []
        func check(_ condition: Bool, _ name: String) {
            print("IKTEST check \(condition ? "PASS" : "FAIL") \(name)")
            if !condition { failures.append(name) }
        }
        let directory = FileManager.default.temporaryDirectory.appending(path: "IkagoChecks-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SessionStore(directory: directory)
        let state = BrowserState(store: store)
        check(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String == "Ikago"
              && Bundle.main.bundleIdentifier == "app.ikago.browser", "Ikago branding uses its own identity")
        check(Bundle.main.url(forResource: "IkagoAppIcon", withExtension: "icns").flatMap(NSImage.init(contentsOf:)) != nil,
              "Ikago icon is packaged for Finder and the closed Dock")
        for page in InternalPage.allCases {
            check(InternalPage(url: page.url) == page
                  && (try? AddressResolver.resolve(page.url, engine: .google)) == page.url,
                  "internal address resolves to \(page.url)")
        }
        check(InternalPage(url: "https://settings") == nil, "only the ikago scheme opens internal pages")
        let tab = state.newTab(url: "https://example.com", select: true)!
        tab.title = "Example"
        state.addBookmark(tab)
        state.addBookmark(tab)
        check(state.bookmarks.count == 1, "bookmarks deduplicate URLs")
        state.closeTab(tab.id, removingPin: true)
        check(state.bookmarks.count == 1, "bookmark survives tab closure")
        state.browserPreferences.hibernationEnabled = true
        state.browserPreferences.hibernationMinutes = 15
        state.browserPreferences.hibernationExceptions = "example.org, MAIL.example.com"
        state.saveNow()
        let restored = BrowserState(store: store)
        check(restored.bookmarks == state.bookmarks && restored.browserPreferences == state.browserPreferences, "bookmarks and memory preferences round-trip")
        if let base = URL(string: browser.state.activeTab?.url ?? ""),
           let url = URL(string: "/icon.svg?cachecheck", relativeTo: base)?.absoluteURL {
            let first = await FaviconCache.shared.image(for: url)
            let second = await FaviconCache.shared.image(for: url)
            check(first != nil && first === second, "favicon requests reuse cached image")
        }
        var legacyJSON = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(state.snapshot()))) as? [String: Any] ?? [:]
        legacyJSON.removeValue(forKey: "browser")
        legacyJSON.removeValue(forKey: "bookmarks")
        if let data = try? JSONSerialization.data(withJSONObject: legacyJSON), let legacy = try? JSONDecoder().decode(Session.self, from: data) {
            try? store.save(legacy)
            let migrated = BrowserState(store: store)
            check(migrated.bookmarks.isEmpty && !migrated.browserPreferences.hibernationEnabled, "older sessions retain safe defaults")
        } else { check(false, "older sessions decode") }
        check(restored.browserPreferences.protects("https://sub.example.org") && !restored.browserPreferences.protects("https://evil-example.org"), "exception domains respect hostname boundaries")
        check(ExtensionCompatibility.reason(manifest: ["permissions": ["notifications"]]) == nil && !ExtensionCompatibility.warnings(manifest: ["permissions": ["notifications"]]).isEmpty, "partial Chrome features warn without blocking install")
        check(ExtensionCompatibility.reason(manifest: ["optional_permissions": ["notifications"]]) == nil, "optional unsupported capability does not block extension")
        check(!ExtensionCompatibility.warnings(manifest: ["permissions": ["nativeMessaging"]]).isEmpty, "Chrome companion app limitation explained")
        check(ExtensionCompatibility.reason(manifest: ["permissions": ["nativeMessaging"]], safari: true) == nil, "Safari companion app messaging allowed")
        do {
            let manager = ExtensionManager.shared
            let id = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
            func package(version: String, permissions: [String], theme: Bool = false) throws -> URL {
                let folder = directory.appending(path: UUID().uuidString)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                var manifest: [String: Any] = ["manifest_version": 3, "name": "Ikago fixture", "version": version, "permissions": permissions]
                if theme { manifest["theme"] = ["colors": [:]] }
                try JSONSerialization.data(withJSONObject: manifest).write(to: folder.appending(path: "manifest.json"))
                return folder
            }
            let installed = try await manager.install(unpackedAt: package(version: "1.0", permissions: []), id: id, fromWebStore: false, approve: false)
            check(installed && manager.contexts[id]?.isLoaded == true, "local extension installs and loads")
            do {
                _ = try await manager.install(unpackedAt: package(version: "2.0", permissions: [], theme: true), id: id, fromWebStore: false, approve: false)
                check(false, "incompatible update rejected")
            } catch {
                check(manager.contexts[id]?.webExtension.version == "1.0", "incompatible update keeps working installed version")
            }
            let expandedFolder = try package(version: "2.0", permissions: ["tabs"])
            let expanded = try await WKWebExtension(resourceBaseURL: expandedFolder)
            check(ExtensionManager.requiresApproval(current: manager.contexts[id]!.webExtension, next: expanded), "update adding permissions requires approval")
            let unchangedFolder = try package(version: "2.0", permissions: [])
            let unchanged = try await WKWebExtension(resourceBaseURL: unchangedFolder)
            check(!ExtensionManager.requiresApproval(current: manager.contexts[id]!.webExtension, next: unchanged), "update with unchanged capabilities can run automatically")
            _ = try await manager.install(unpackedAt: package(version: "1.0", permissions: []), id: id, fromWebStore: true, approve: false)
            await manager.checkForUpdates(force: true, download: { _ in try package(version: "2.0", permissions: []) })
            check(manager.contexts[id]?.webExtension.version == "2.0", "updater installs newer package with unchanged capabilities")
            await manager.checkForUpdates(force: true, download: { _ in try package(version: "3.0", permissions: ["tabs"]) })
            check(manager.contexts[id]?.webExtension.version == "2.0" && manager.updateMessage.contains("permission review"), "automatic updater defers expanded permissions")
            await manager.checkForUpdates(force: true, reviewPermissions: true, download: { _ in try package(version: "3.0", permissions: ["tabs"]) })
            check(manager.contexts[id]?.webExtension.version == "3.0", "permission review installs approved update")
            await manager.checkForUpdates(force: true, download: { _ in try package(version: "4.0", permissions: [], theme: true) })
            check(manager.contexts[id]?.webExtension.version == "3.0" && !manager.updateDetails.isEmpty, "unsupported update preserves installed version and reports reason")
            await manager.checkForUpdates(force: true, download: { _ in throw URLError(.notConnectedToInternet) })
            check(manager.contexts[id]?.webExtension.version == "3.0", "download failure preserves installed extension")
            manager.automaticUpdates = false
            manager.readUpdatePreferences()
            check(!manager.automaticUpdates, "automatic-update setting persists")
            await manager.setEnabled(id, false)
            check(manager.contexts[id] == nil, "extension can be disabled")
            await manager.checkForUpdates(force: true, download: { _ in try package(version: "5.0", permissions: ["tabs"]) })
            check(manager.records.first { $0.id == id }?.enabled == false && manager.contexts[id] == nil, "update preserves disabled state")
            await manager.setEnabled(id, true)
            check(manager.contexts[id]?.isLoaded == true, "extension can be re-enabled")
            manager.remove(id)
        } catch { check(false, "extension fixtures: \(error.localizedDescription)") }

        let live = browser.state
        if let background = live.tabs.first(where: { !live.visibleTabIDs.contains($0.id) && browser.content.controller(for: $0.id)?.page != nil }),
           let controller = browser.content.controller(for: background.id), controller.page != nil {
            live.browserPreferences.hibernationEnabled = true
            live.browserPreferences.hibernationMinutes = 1
            live.browserPreferences.protectPinnedTabs = true
            live.browserPreferences.hibernationExceptions = ""
            let clock = Date()
            browser.content.hibernation.check(now: clock)
            background.isPlayingAudio = true
            browser.content.hibernation.check(now: clock.addingTimeInterval(120))
            check(!background.isHibernating, "audible background tab stays awake")
            background.isPlayingAudio = false
            background.pinned = true
            browser.content.hibernation.check(now: clock.addingTimeInterval(240))
            check(!background.isHibernating, "protected pinned tab stays awake")
            background.pinned = false
            background.cameraActive = true
            browser.content.hibernation.check(now: clock.addingTimeInterval(360))
            check(!background.isHibernating, "camera tab stays awake")
            background.cameraActive = false
            background.microphoneActive = true
            browser.content.hibernation.check(now: clock.addingTimeInterval(480))
            check(!background.isHibernating, "microphone tab stays awake")
            background.microphoneActive = false
            live.browserPreferences.hibernationExceptions = "127.0.0.1"
            browser.content.hibernation.check(now: clock.addingTimeInterval(600))
            check(!background.isHibernating, "site exception stays awake")
            live.browserPreferences.hibernationExceptions = ""
            live.browserPreferences.hibernationEnabled = false
            browser.content.hibernation.check(now: clock.addingTimeInterval(720))
            check(!background.isHibernating, "disabling hibernation keeps background tab awake")
            live.browserPreferences.hibernationEnabled = true
            browser.content.hibernation.check(now: clock.addingTimeInterval(840))
            check(background.isHibernating && controller.page == nil, "idle background web view released")
            check(browser.activeController?.page != nil, "visible tab stays awake")
            live.select(background.id)
            try? await Task.sleep(for: .seconds(2))
            check(controller.page != nil && !background.isHibernating, "selecting sleeping tab recreates page")
        } else { check(false, "two loaded fixture tabs available for hibernation") }
        NewProfileChecks.run(check)
        print("IKTEST featurechecks \(failures.isEmpty ? "PASS" : "FAIL") failures=\(failures.count)")
    }
}
#endif
