import WebKit

/// Only known blockers are rejected. Passing a manifest check isn't a runtime guarantee.
enum ExtensionCompatibility {
    struct Unsupported: LocalizedError {
        let reason: String
        var errorDescription: String? { "Not supported in Ikago. \(reason)" }
    }

    static func reason(manifest: [String: Any], safari: Bool = false) -> String? {
        if manifest["theme"] != nil { return "Chrome themes cannot change Ikago's appearance. Use Settings ▸ Appearance." }
        if manifest["app"] != nil { return "Chrome apps are not browser extensions." }
        return nil
    }

    /// Missing optional functionality is a warning, not a reason to refuse the whole package.
    static func warnings(manifest: [String: Any], safari: Bool = false) -> [String] {
        let permissions = Set(manifest["permissions"] as? [String] ?? [])
        var warnings: [String] = []
        if !safari, permissions.contains("nativeMessaging") {
            warnings.append("Companion-app connections are unavailable for this Chrome package. Features that need its desktop app may not work; the app’s Safari extension may provide that integration.")
        }
        let unavailable: Set<String> = ["debugger", "proxy", "notifications", "gcm", "platformKeys", "enterprise.platformKeys", "webRequestBlocking"]
        let required = permissions.intersection(unavailable).sorted()
        if !required.isEmpty { warnings.append("Some features may not work: \(required.joined(separator: ", ")). You can still install and try the extension.") }
        return warnings
    }

    @MainActor
    static func validate(_ ext: WKWebExtension, safari: Bool = false) throws {
        if let reason = reason(manifest: ext.manifest, safari: safari) { throw Unsupported(reason: reason) }
        let blocking: Set<Int> = [WKWebExtension.Error.invalidManifest.rawValue,
                                  WKWebExtension.Error.unsupportedManifestVersion.rawValue,
                                  WKWebExtension.Error.invalidDeclarativeNetRequestEntry.rawValue,
                                  WKWebExtension.Error.invalidBackgroundPersistence.rawValue]
        if let error = ext.errors.first(where: { blocking.contains(($0 as NSError).code) }) {
            throw Unsupported(reason: error.localizedDescription)
        }
    }
}

/// Deduplicates store preflight requests; temporary network failures stay retryable.
@MainActor
final class ExtensionStoreStatus {
    static let shared = ExtensionStoreStatus()
    private var pending: [String: Task<[String: String], Never>] = [:]
    private var results: [String: (Date, [String: String])] = [:]

    func status(_ id: String) async -> [String: String] {
        let manager = ExtensionManager.shared
        if let failure = manager.failures[id] {
            return ["state": failure.hasPrefix("Not supported") ? "unsupported" : "error", "reason": failure]
        }
        if let context = manager.contexts[id], let error = context.errors.first {
            return ["state": "error", "reason": "Extension problem: \(error.localizedDescription). See Settings ▸ Extensions."]
        }
        if manager.isInstalled(id) { return ["state": "installed", "reason": "Installed. Check Settings ▸ Extensions for runtime problems."] }
        if let (date, result) = results[id], Date().timeIntervalSince(date) < 900 { return result }
        if let task = pending[id] { return await task.value }
        let task = Task<[String: String], Never> {
            do {
                let folder = try await WebStoreInstaller.download(id: id)
                defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
                let ext = try await WKWebExtension(resourceBaseURL: folder)
                try ExtensionCompatibility.validate(ext)
                let warnings = ExtensionCompatibility.warnings(manifest: ext.manifest)
                return ["state": warnings.isEmpty ? "none" : "limited", "reason": warnings.isEmpty
                        ? "Runs directly in Ikago using WebKit’s extension support. Compatibility can vary by feature."
                        : "Limited support. " + warnings.joined(separator: " ")]
            } catch let error as ExtensionCompatibility.Unsupported {
                return ["state": "unsupported", "reason": error.localizedDescription]
            } catch let error as NSError where error.domain == WKWebExtension.errorDomain {
                return ["state": "unsupported", "reason": "Not supported in Ikago. \(error.localizedDescription)"]
            } catch {
                return ["state": "error", "reason": "Compatibility could not be checked: \(error.localizedDescription). You can retry the install."]
            }
        }
        pending[id] = task
        let result = await task.value
        pending[id] = nil
        if result["state"] != "error" {
            if results.count >= 100 { results.removeAll() }
            results[id] = (Date(), result)
        }
        return result
    }
}
