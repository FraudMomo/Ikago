import Foundation
import Observation

/// One action selects all supported data, the current Space and the correct browser key.
@MainActor
@Observable
final class BrowserImportModel {
    typealias AccessPreparer = @MainActor (DetectedBrowserProfile, Bool) async throws -> BrowserImportAccess.Grant?
    typealias Reader = @Sendable (DetectedBrowserProfile) async throws -> BrowserImportData
    private(set) var profiles: [DetectedBrowserProfile] = []
    private(set) var discovering = false
    private(set) var importingID: String?
    private(set) var completed: Set<String> = []
    private(set) var result: String?
    private(set) var notes: [String] = []
    private(set) var failed = false
    private(set) var accessNeededFor: DetectedBrowserProfile?
    @ObservationIgnored private let home: URL
    @ObservationIgnored private let reader: Reader
    @ObservationIgnored private let prepareAccess: AccessPreparer
    @ObservationIgnored private let includeInstalledApps: Bool

    init(home: URL? = nil, accessPreparer: AccessPreparer? = nil, reader: Reader? = nil) {
        if let accessPreparer { prepareAccess = accessPreparer }
        else if WebProfiles.isTestMode || home != nil || reader != nil { prepareAccess = { _, _ in nil } }
        else { prepareAccess = { source, force in try await BrowserImportAccess.prepare(source, force: force) } }
        includeInstalledApps = home == nil && !WebProfiles.isTestMode
        self.home = home ?? (WebProfiles.isTestMode ? SessionStore.testDirectory.appending(path: "ImportSources") : FileManager.default.homeDirectoryForCurrentUser)
        self.reader = reader ?? { source in
            try await Task.detached {
                try BrowserProfileImporter.read(source.directory, kind: source.kind, decryptWith: source.cookieKey)
            }.value
        }
    }

    func refresh() async {
        guard !discovering, importingID == nil else { return }
        discovering = true
        defer { discovering = false }
        let root = home
        let installed = includeInstalledApps ? BrowserProfileDiscovery.installedBrowsers() : []
        let found = await Task.detached { BrowserProfileDiscovery.discover(home: root, installedBrowsers: installed) }.value
        guard !Task.isCancelled else { return }
        profiles = found
    }

    func importProfile(_ source: DetectedBrowserProfile, into state: BrowserState, requestAccess: Bool = false) async {
        guard importingID == nil, !state.isFrozen else { return }
        let destination = state.activeSpace
        importingID = source.id
        result = nil; notes = []; failed = false; accessNeededFor = nil
        defer { importingID = nil }
        do {
            let grant = try await prepareAccess(source, requestAccess)
            defer { grant?.end() }
            guard !Task.isCancelled, !state.isFrozen else { return }
            let data = try await reader(source)
            notes = data.notes
            guard data.hasData else {
                failed = true
                if !data.accessIssues.isEmpty { showAccessRequired(source) }
                else { result = "No available data could be imported from \(source.browser)." }
                return
            }
            var selection = ImportSelection()
            selection.cookies = true // The Import action explicitly includes available website logins.
            let summary = await state.applyImport(data, selection: selection, to: destination.id)
            guard !state.isFrozen, state.spaces.contains(where: { $0.id == destination.id }) else {
                failed = true; result = summary; return
            }
            if data.accessIssues.isEmpty { completed.insert(source.id) }
            else { showAccessRequired(source) }
            result = "\(summary) Destination: \(destination.name)." + (accessNeededFor == nil ? "" : " Some browser data is blocked. Allow access and retry to finish importing.")
        } catch is CancellationError {
            result = "Import cancelled. No data was imported."
            accessNeededFor = source.kind == .file ? nil : source
        } catch {
            failed = true
            result = "Ikago couldn’t read \(source.browser)’s data."
            notes = [error.localizedDescription]
            if ImportAccessError.isPermissionDenied(error) || (error as NSError).domain == "Ikago.ImportAccess" { showAccessRequired(source) }
        }
    }

    func retryWithAccess(into state: BrowserState) async {
        guard let source = accessNeededFor else { return }
        await importProfile(source, into: state, requestAccess: true)
    }

    private func showAccessRequired(_ source: DetectedBrowserProfile) {
        failed = true
        guard source.kind != .file else {
            result = "The selected file couldn’t be read. Choose it again using Import an Exported File."
            return
        }
        accessNeededFor = source
        result = "macOS is blocking access to \(source.browser)’s data. Allow access to the detected profile folder to continue importing."
    }

    func importFile(_ url: URL, into state: BrowserState) async {
        let source = DetectedBrowserProfile(browser: "exported file", name: url.lastPathComponent, directory: url, kind: .file, cookieKey: nil)
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        await importProfile(source, into: state)
    }
}
