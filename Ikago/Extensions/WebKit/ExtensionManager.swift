import AppKit
import WebKit

/// Installed web extensions (Chrome Web Store or unpacked folders), loaded into one shared
/// `WKWebExtensionController` that every Space's tabs use. Extensions live unpacked in
/// Application Support/Ikago/Extensions/<id>; `extensions.json` lists them.
@MainActor
@Observable
final class ExtensionManager: NSObject {
    static let shared = ExtensionManager()

    struct Record: Codable, Identifiable, Equatable {
        var id: String          // Chrome Web Store ID, or a generated one for local installs
        var enabled = true
        var fromWebStore = false
        /// WebKit-generated resource origin, retained for origin-scoped storage.
        var resourceOrigin: String? = nil
        /// A Safari web extension inside an installed Mac app, loaded in place (updates with the app).
        var appexPath: String?
    }

    var automaticUpdates = true { didSet { saveUpdatePreferences() } }
    var lastUpdateCheck: Date?
    var checkingUpdates = false
    var updateDetails: [String] = []
    var updateMessage = "Web Store extensions are checked daily. Safari extensions update with their apps."
    var installIssue: String?
    @ObservationIgnored var updateTask: Task<Void, Never>?
    var installing: Set<String> = []
    var failures: [String: String] = [:]
    private(set) var records: [Record] = []
    /// Bumped when an action's icon, badge or title changes, so the toolbar redraws.
    private(set) var revision = 0
    @ObservationIgnored var controllers: [String: WKWebExtensionController] = [:]
    private(set) var contexts: [String: WKWebExtensionContext] = [:]
    /// The browser window, for tabs/windows the extensions see.
    @ObservationIgnored weak var browser: BrowserWindowController?
    /// The window extensions were last told has focus, so becoming key again (switching back from another app)
    /// doesn't repeat it: each report wakes every listening extension's background page, launching a web
    /// process on the main thread.
    @ObservationIgnored weak var focusedWindow: BrowserWindowController?
    /// Toolbar buttons register here so popups can anchor to them.
    @ObservationIgnored var anchors: [String: NSView] = [:]
    /// The popover currently shown for an extension action (one at a time).
    @ObservationIgnored var presentedPopover: NSPopover?

    // MARK: Controllers

    /// One controller for all Spaces, so extensions run everywhere. Their own storage and
    /// background pages use the default data store; isolated Spaces keep separate cookies.
    func controller(for profileID: String) -> WKWebExtensionController {
        if let controller = controllers["Default"] { return controller }
        let configuration: WKWebExtensionController.Configuration
        if let identifier = WebProfiles.persistenceTestIdentifier {
            configuration = .init(identifier: identifier)
        } else { configuration = WebProfiles.isTestMode ? .nonPersistent() : .init(identifier: UUID(uuidString: "B4911059-F30D-41BE-980A-483C626CF752")!) }
        configuration.defaultWebsiteDataStore = WebProfiles.dataStore(for: "Default")
        let controller = WKWebExtensionController(configuration: configuration)
        controller.delegate = self
        controllers["Default"] = controller
        return controller
    }

    var allControllers: [WKWebExtensionController] { Array(controllers.values) }

    /// Extensions that run in the Space's tabs (all of them, until per-Space installs exist).
    var loaded: [WKWebExtensionContext] {
        records.filter(\.enabled).compactMap { contexts[$0.id] }
    }

    func context(for url: URL) -> WKWebExtensionContext? {
        guard BrowserRuntime.runs(.webkit) else { return nil }
        if let context = controller(for: "Default").extensionContext(for: url) { return context }
        if ExtensionURL.isExtension(url.absoluteString), let id = url.host { return contexts[id] }
        return nil
    }

    // MARK: Startup

    /// Loads every enabled extension. Call before the first tab is created so content
    /// scripts reach the first page load.
    func loadInstalled() async {
        readUpdatePreferences()
        records = Self.readRecords()
        for record in records where record.enabled {
            do { try await load(record) } catch { failures[record.id] = error.localizedDescription }
        }
    }

    @discardableResult
    func load(_ savedRecord: Record) async throws -> Record {
        var record = savedRecord
        let webExtension: WKWebExtension
        if let path = record.appexPath {
            guard let bundle = Bundle(path: path) else { throw Self.error("The app containing this extension was removed") }
            webExtension = try await WKWebExtension(appExtensionBundle: bundle)
        } else {
            webExtension = try await WKWebExtension(resourceBaseURL: Self.directory.appending(path: record.id, directoryHint: .isDirectory))
        }
        try ExtensionCompatibility.validate(webExtension, safari: record.appexPath != nil)
        let context = WKWebExtensionContext(for: webExtension)
        context.uniqueIdentifier = record.id
        // Keep WebKit's own scheme/host stable: IndexedDB and localStorage use this origin.
        if let origin = record.resourceOrigin.flatMap(URL.init(string:)), origin.scheme == "webkit-extension", origin.host != nil {
            context.baseURL = origin
        }
        record.resourceOrigin = context.baseURL.absoluteString
        context.isInspectable = WebProfiles.developerTools
        Self.grantRequested(context)
        try controller(for: "Default").load(context)
        contexts[record.id] = context
        failures[record.id] = nil
        if let index = records.firstIndex(where: { $0.id == record.id }) {
            records[index] = record
            saveRecords()
        }
        return record
    }

    /// The user approved everything the manifest requests when installing.
    private static func grantRequested(_ context: WKWebExtensionContext) {
        let ext = context.webExtension
        for permission in ext.requestedPermissions { context.setPermissionStatus(.grantedExplicitly, for: permission) }
        for pattern in ext.requestedPermissionMatchPatterns { context.setPermissionStatus(.grantedExplicitly, for: pattern) }
    }

    // MARK: Install / enable / remove

    /// Installs the unpacked extension at `folder` (moved into place) after the user approves.
    @discardableResult
    func install(unpackedAt folder: URL, id: String, fromWebStore: Bool, approve: Bool = true, updating: Bool = false) async throws -> Bool {
        guard BrowserRuntime.runs(.webkit) else { throw Self.error("Extension installation is not yet connected to CEF.") }
        guard installing.insert(id).inserted else { throw Self.error("This extension is already being installed") }
        defer { installing.remove(id); try? FileManager.default.removeItem(at: folder) }
        installIssue = nil
        let preview = try await WKWebExtension(resourceBaseURL: folder)
        try ExtensionCompatibility.validate(preview)
        if approve, !(await ExtensionPrompts.confirmInstall(preview, in: browser?.window)) { return false }
        if updating, !records.contains(where: { $0.id == id }) { return false }
        let target = Self.directory.appending(path: id, directoryHint: .isDirectory)
        let backup = Self.directory.appending(path: ".backup-\(id)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        let oldRecord = records.first { $0.id == id }
        let oldContext = contexts[id]
        if let oldContext { try oldContext.webExtensionController?.unload(oldContext) }
        contexts[id] = nil
        let hadTarget = FileManager.default.fileExists(atPath: target.path)
        do {
            if hadTarget { try FileManager.default.moveItem(at: target, to: backup) }
            try FileManager.default.moveItem(at: folder, to: target)
            var record = oldRecord ?? Record(id: id, fromWebStore: fromWebStore)
            record.fromWebStore = fromWebStore
            if record.enabled { record = try await load(record) }
            records.removeAll { $0.id == id }
            records.append(record)
            saveRecords()
            try? FileManager.default.removeItem(at: backup)
            failures[id] = nil
            if fromWebStore && !updating { ExtensionSync.added(id) }
            return true
        } catch {
            if FileManager.default.fileExists(atPath: backup.path) || !hadTarget {
                try? FileManager.default.removeItem(at: target)
            }
            if FileManager.default.fileExists(atPath: backup.path) {
                try? FileManager.default.moveItem(at: backup, to: target)
            }
            if let oldRecord, oldRecord.enabled { _ = try? await load(oldRecord) }
            throw error
        }
    }

    /// Adds a Safari web extension that ships inside a Mac app (e.g. 1Password, Bitwarden).
    func installSafariExtension(at appex: URL) async throws {
        guard BrowserRuntime.runs(.webkit) else { throw Self.error("Safari extensions require the WebKit engine.") }
        guard let bundle = Bundle(url: appex) else { throw Self.error("Not an app extension") }
        let preview = try await WKWebExtension(appExtensionBundle: bundle)
        try ExtensionCompatibility.validate(preview, safari: true)
        guard await ExtensionPrompts.confirmInstall(preview, in: browser?.window) else { return }
        let id = WebStoreInstaller.localID(for: appex)
        if let existing = contexts[id] { try? existing.webExtensionController?.unload(existing) }
        let origin = records.first { $0.id == id }?.resourceOrigin
        records.removeAll { $0.id == id }
        let record = Record(id: id, resourceOrigin: origin, appexPath: appex.path)
        records.append(record)
        saveRecords()
        try await load(record)
    }

    /// Safari web extensions bundled in apps under /Applications and ~/Applications.
    nonisolated static func safariExtensionsOnThisMac() -> [URL] {
        let fm = FileManager.default
        let roots = [URL(fileURLWithPath: "/Applications"), fm.homeDirectoryForCurrentUser.appending(path: "Applications")]
        var found: [URL] = []
        for root in roots {
            for app in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] where app.pathExtension == "app" {
                let plugIns = app.appending(path: "Contents/PlugIns")
                for appex in (try? fm.contentsOfDirectory(at: plugIns, includingPropertiesForKeys: nil)) ?? []
                where appex.pathExtension == "appex" {
                    let info = NSDictionary(contentsOf: appex.appending(path: "Contents/Info.plist"))
                    let point = (info?["NSExtension"] as? [String: Any])?["NSExtensionPointIdentifier"] as? String
                    if point == "com.apple.Safari.web-extension" { found.append(appex) }
                }
            }
        }
        return found
    }

    func setEnabled(_ id: String, _ enabled: Bool) async {
        guard !installing.contains(id) else { return }
        guard let index = records.firstIndex(where: { $0.id == id }), records[index].enabled != enabled else { return }
        records[index].enabled = enabled
        saveRecords()
        if records[index].fromWebStore, records[index].appexPath == nil { ExtensionSync.setEnabled(id, enabled) }
        if enabled {
            do { _ = try await load(records[index]) } catch { failures[id] = error.localizedDescription }
        } else if let context = contexts.removeValue(forKey: id) {
            try? context.webExtensionController?.unload(context)
        }
    }

    func remove(_ id: String) {
        guard !installing.contains(id) else { return }
        if let context = contexts.removeValue(forKey: id) { try? context.webExtensionController?.unload(context) }
        let wasTopBar = records.first { $0.id == id }?.appexPath != nil
        if records.first(where: { $0.id == id })?.fromWebStore == true, !wasTopBar { ExtensionSync.removed(id) }
        records.removeAll { $0.id == id }
        failures[id] = nil
        saveRecords()
        // Safari extensions belong to their app; only our own unpacked copies are deleted.
        if !wasTopBar { try? FileManager.default.removeItem(at: Self.directory.appending(path: id, directoryHint: .isDirectory)) }
    }

    func isInstalled(_ id: String) -> Bool { records.contains { $0.id == id } }

    func actionDidChange() { revision &+= 1 }

    // MARK: Persistence

    static var directory: URL {
        let base = WebProfiles.isTestMode
            ? SessionStore.testDirectory
            : AppIdentity.dataDirectory
        return base.appending(path: "Extensions", directoryHint: .isDirectory)
    }

    private static var recordsFile: URL { directory.appending(path: "extensions.json") }

    private static func readRecords() -> [Record] {
        guard let data = try? Data(contentsOf: recordsFile) else { return [] }
        return (try? JSONDecoder().decode([Record].self, from: data)) ?? []
    }

    func saveRecords() {
        do {
            try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(records).write(to: Self.recordsFile, options: .atomic)
        } catch {
            NSLog("Ikago: extensions list not saved: \(error)")
        }
    }
}
