import AppKit
import IKCEFBridge

/// Chromium extensions for one Space, managed through Chromium's own extension service on a hidden
/// chrome://extensions page. Ikago draws all the UI.
@MainActor
@Observable
final class ChromiumExtensions {
    static let shared = ChromiumExtensions()

    struct Item: Identifiable, Equatable {
        let id: String
        var name: String
        var version: String
        var summary: String
        var enabled: Bool
        var path: String?
        var icon: NSImage?
        /// The action's popup page, relative to the extension's root.
        var popup: String?
        /// The page it puts on new tabs (`chrome_url_overrides.newtab`), relative to its root.
        var newTabPage: String?
    }

    private(set) var items: [Item] = []
    private(set) var profile: String?
    private(set) var busy = false
    var issue: String?
    @ObservationIgnored private var manager: (profile: String, tool: HiddenChromiumPage)?
    @ObservationIgnored private var idleClose: Task<Void, Never>?

    /// Keeps store installs, because unpacked extensions load from where they are.
    static var storeFolder: URL { AppIdentity.dataDirectory.appending(path: "Chromium Extensions", directoryHint: .isDirectory) }

    func refresh(profile: String) async {
        await perform(profile) { _ in }
    }

    func setEnabled(_ item: Item, enabled: Bool, profile: String) async {
        await perform(profile) { tool in
            try await tool.run("chrome.management.setEnabled(\(Self.quoted(item.id)), \(enabled))")
        }
        if issue == nil, let id = Self.storeID(of: item) { ExtensionSync.setEnabled(id, enabled) }
    }

    /// Installs an unpacked extension folder. Ikago chose the folder, so Chromium shows no picker.
    func install(folder: URL, profile: String) async {
        await perform(profile) { tool in
            try await tool.run("chrome.developerPrivate.updateProfileConfiguration({inDeveloperMode: true})")
            IKCEFNativeTools.setNextFolderSelection(folder.path)
            defer { IKCEFNativeTools.setNextFolderSelection(nil) }
            let failure = try await tool.run("chrome.developerPrivate.loadUnpacked({failQuietly: true, populateError: true})")
            if let failure, let data = failure.data(using: .utf8),
               let error = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let message = error["error"] as? String {
                throw CEFError.script(message)
            }
        }
    }

    /// Downloads from the Chrome Web Store's public update service and installs the unpacked copy.
    func install(storeLink: String, profile: String) async {
        guard let id = WebStoreInstaller.extensionID(fromStoreURL: storeLink) ?? (WebStoreInstaller.isValidID(storeLink) ? storeLink : nil) else {
            issue = "That isn’t a Chrome Web Store extension link."
            return
        }
        busy = true
        do {
            let unpacked = try await WebStoreInstaller.download(id: id)
            defer { try? FileManager.default.removeItem(at: unpacked.deletingLastPathComponent()) }
            await install(unpacked: unpacked, storeID: id, profile: profile)
        } catch {
            busy = false
            issue = error.localizedDescription
        }
    }

    /// Moves a downloaded, verified store package into place and loads it into `profile`'s Space.
    func install(unpacked: URL, storeID id: String, profile: String) async {
        guard WebStoreInstaller.isValidID(id) else { issue = "Not a Chrome Web Store extension ID."; return }
        do {
            let destination = Self.storeFolder.appending(path: id, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: Self.storeFolder, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: unpacked, to: destination)
            await install(folder: destination, profile: profile)
            if issue == nil { ExtensionSync.added(id) }
        } catch {
            busy = false
            issue = error.localizedDescription
        }
    }

    /// The extension removes itself, which is the one route Chromium allows without its own dialog.
    func remove(_ item: Item, profile: String) async {
        if let id = Self.storeID(of: item) { ExtensionSync.removed(id) }
        await perform(profile) { _ in
            try CEFSessions.prepare(profile)
            let page = try await HiddenChromiumPage.open {
                try IKCEFNativeTools.openExtensionResource(item.id, path: "manifest.json", profile: profile)
            }
            defer { page.close() }
            // The page goes away with the extension, so a lost reply here is success; the refresh confirms it.
            _ = try? await page.run("chrome.management.uninstallSelf({showConfirmDialog: false})")
            try await Task.sleep(for: .milliseconds(200))
            if let path = item.path, URL(fileURLWithPath: path).deletingLastPathComponent().standardizedFileURL == Self.storeFolder.standardizedFileURL {
                try? FileManager.default.removeItem(atPath: path)
            }
        }
    }

    func shutDown() {
        idleClose?.cancel()
        manager?.tool.close()
        manager = nil
    }

    private func perform(_ profile: String, _ work: (HiddenChromiumPage) async throws -> Void) async {
        idleClose?.cancel()
        busy = true
        defer { busy = false; scheduleIdleClose() }
        do {
            let tool = try await managerPage(profile: profile)
            try await work(tool)
            issue = nil
            try await reload(tool, profile: profile)
        } catch {
            issue = error.localizedDescription
        }
    }

    private func managerPage(profile: String) async throws -> HiddenChromiumPage {
        if let manager, manager.profile == profile, !manager.tool.page.isClosed { return manager.tool }
        manager?.tool.close()
        manager = nil
        try CEFSessions.prepare(profile)
        let tool = try await HiddenChromiumPage.open { try IKCEFNativeTools.openExtensions(forProfile: profile) }
        manager = (profile, tool)
        return tool
    }

    private func reload(_ tool: HiddenChromiumPage, profile: String) async throws {
        let json = try await tool.run("""
        (async () => {
          const items = await chrome.developerPrivate.getExtensionsInfo({includeDisabled: true, includeTerminated: true});
          return items.map(item => {
            return {id: item.id, name: item.name, version: item.version, summary: item.description,
                    enabled: item.state === 'ENABLED', path: item.prettifiedPath || null, icon: item.iconUrl};
          });
        })()
        """)
        guard let data = json?.data(using: .utf8), let list = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw CEFError.noResult
        }
        items = list.compactMap(Self.item).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        self.profile = profile
    }

    private static func item(_ value: [String: Any]) -> Item? {
        guard let id = value["id"] as? String, let name = value["name"] as? String else { return nil }
        let path = (value["path"] as? String).map { ($0 as NSString).expandingTildeInPath }
        var icon: NSImage?
        // Chromium supplies icons as data URLs; anything else falls back to the generic tile.
        if let encoded = value["icon"] as? String, encoded.hasPrefix("data:"), let comma = encoded.firstIndex(of: ","),
           let data = Data(base64Encoded: String(encoded[encoded.index(after: comma)...])) { icon = NSImage(data: data) }
        return Item(id: id, name: name, version: value["version"] as? String ?? "", summary: value["summary"] as? String ?? "",
                    enabled: value["enabled"] as? Bool ?? false, path: path, icon: icon, popup: path.flatMap(popup(inFolder:)),
                    newTabPage: path.flatMap(newTabPage(inFolder:)))
    }

    private static func newTabPage(inFolder path: String) -> String? {
        let manifest = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).appending(path: "manifest.json")
        guard let data = try? Data(contentsOf: manifest),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (object["chrome_url_overrides"] as? [String: Any])?["newtab"] as? String
    }

    private static func popup(inFolder path: String) -> String? {
        let manifest = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).appending(path: "manifest.json")
        guard let data = try? Data(contentsOf: manifest),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let action = (object["action"] ?? object["browser_action"]) as? [String: Any]
        return action?["default_popup"] as? String
    }

    /// The Web Store ID of an extension Ikago installed from the store: its folder's name. Chromium's own
    /// ID differs, because it loads the unpacked copy.
    static func storeID(of item: Item) -> String? {
        guard let path = item.path else { return nil }
        let folder = URL(fileURLWithPath: path).standardizedFileURL
        guard folder.deletingLastPathComponent() == storeFolder.standardizedFileURL else { return nil }
        let id = folder.lastPathComponent
        return WebStoreInstaller.isValidID(id) ? id : nil
    }

    private static func quoted(_ value: String) -> String {
        String(data: (try? JSONEncoder().encode(value)) ?? Data(), encoding: .utf8) ?? "\"\""
    }

    private func scheduleIdleClose() {
        idleClose = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            self?.shutDown()
        }
    }
}
