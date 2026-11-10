import WebKit

extension ExtensionManager {
    struct UpdatePreferences: Codable {
        var automatic = true
        var lastCheck: Date?
    }

    func startUpdates() {
        guard !WebProfiles.isTestMode else { return }
        updateTask?.cancel()
        updateTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.automaticUpdates { await self.checkForUpdates() }
                try? await Task.sleep(for: .seconds(3600))
            }
        }
    }

    func readUpdatePreferences() {
        guard let data = try? Data(contentsOf: Self.directory.appending(path: "updates.json")),
              let settings = try? JSONDecoder().decode(UpdatePreferences.self, from: data) else { return }
        lastUpdateCheck = settings.lastCheck
        automaticUpdates = settings.automatic
    }

    func saveUpdatePreferences() {
        let settings = UpdatePreferences(automatic: automaticUpdates, lastCheck: lastUpdateCheck)
        try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        try? JSONEncoder().encode(settings).write(to: Self.directory.appending(path: "updates.json"), options: .atomic)
    }

    /// New capabilities always require another install approval. A failed update keeps the old copy.
    func checkForUpdates(force: Bool = false, reviewPermissions: Bool = false,
                         download: (String) async throws -> URL = { try await WebStoreInstaller.download(id: $0) }) async {
        guard !checkingUpdates else { return }
        if !force, let lastUpdateCheck, Date().timeIntervalSince(lastUpdateCheck) < 86400 { return }
        checkingUpdates = true
        updateMessage = "Checking for updates…"
        defer { checkingUpdates = false }
        var updated = 0, needsReview = 0, failed = 0
        updateDetails = []
        for record in records where record.fromWebStore && record.appexPath == nil {
            do {
                let folder = try await download(record.id)
                defer {
                    try? FileManager.default.removeItem(at: folder)
                    if folder.lastPathComponent == "unpacked", folder.deletingLastPathComponent().lastPathComponent.hasPrefix("ikago-ext-") {
                        try? FileManager.default.removeItem(at: folder.deletingLastPathComponent())
                    }
                }
                guard records.contains(where: { $0.id == record.id }) else { continue }
                let next = try await WKWebExtension(resourceBaseURL: folder)
                let current = try await WKWebExtension(resourceBaseURL: Self.directory.appending(path: record.id))
                guard let version = next.version, let oldVersion = current.version,
                      version.compare(oldVersion, options: .numeric) == .orderedDescending else { continue }
                try ExtensionCompatibility.validate(next)
                let expanded = Self.requiresApproval(current: current, next: next)
                if expanded && !reviewPermissions { needsReview += 1; continue }
                if try await install(unpackedAt: folder, id: record.id, fromWebStore: true, approve: expanded, updating: true) { updated += 1 }
            } catch {
                failed += 1
                let name = contexts[record.id]?.webExtension.displayName ?? record.id
                updateDetails.append("\(name): \(error.localizedDescription)")
            }
        }
        lastUpdateCheck = Date()
        saveUpdatePreferences()
        updateMessage = "\(updated) updated.\(needsReview > 0 ? " \(needsReview) need permission review; click Review Updates." : "")\(failed > 0 ? " \(failed) could not be updated; existing versions were kept." : "")"
    }

    static func requiresApproval(current: WKWebExtension, next: WKWebExtension) -> Bool {
        !Set(next.manifest["permissions"] as? [String] ?? []).isSubset(of: Set(current.manifest["permissions"] as? [String] ?? []))
            || !Set(next.manifest["host_permissions"] as? [String] ?? []).isSubset(of: Set(current.manifest["host_permissions"] as? [String] ?? []))
            || !next.requestedPermissions.isSubset(of: current.requestedPermissions)
            || !next.requestedPermissionMatchPatterns.isSubset(of: current.requestedPermissionMatchPatterns)
            || extraScopes(next.manifest) != extraScopes(current.manifest)
    }

    private static func extraScopes(_ manifest: [String: Any]) -> Data? {
        var scope: [String: Any] = [:]
        for key in ["optional_permissions", "optional_host_permissions", "externally_connectable"] {
            if let value = manifest[key] { scope[key] = value }
        }
        let scripts = manifest["content_scripts"] as? [[String: Any]] ?? []
        scope["content_matches"] = scripts.flatMap { $0["matches"] as? [String] ?? [] }.sorted()
        return try? JSONSerialization.data(withJSONObject: scope, options: [.sortedKeys])
    }
}
