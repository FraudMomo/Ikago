import Foundation

/// Settings ▸ General ▸ Remove Chromium: turns the Chromium engine off and removes everything it keeps on this Mac:
/// its profiles (website data, caches, history it kept), its extensions and an older profile folder. Chromium itself
/// stays inside Ikago, which is signed as one app: removing a part of it would break the signature, and an update would
/// put it back. It just never starts again unless it is chosen as an engine.
///
/// Its folders can't be removed while Chromium runs, so a launch that runs it marks them, and the next launch that
/// doesn't removes them before anything else starts (`applyPendingAtLaunch`).
@MainActor
enum ChromiumRemoval {
    private static let pendingKey = "RemoveChromiumDataAtLaunch"

    /// Everything Chromium leaves in Ikago's data folder (`root`: the session folder, a temporary one in checks).
    nonisolated static func folders(in root: URL) -> [URL] {
        ["Chromium", "Chromium Extensions", "CEF"].map { root.appending(path: $0, directoryHint: .isDirectory) }
    }

    static var root: URL { SessionStore.standard.directory }

    /// Bytes on disk, counted off the main thread.
    nonisolated static func size(in root: URL) async -> Int64 {
        await Task.detached(priority: .utility) { measure(root) }.value
    }

    nonisolated private static func measure(_ root: URL) -> Int64 {
        var total: Int64 = 0
        for folder in folders(in: root) {
            guard let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]) else { continue }
            while let file = files.nextObject() as? URL {
                let values = try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey])
                if values?.isRegularFile == true { total += Int64(values?.totalFileAllocatedSize ?? 0) }
            }
        }
        return total
    }

    /// Removal waits for a launch without Chromium.
    static var isPending: Bool { !WebProfiles.isTestMode && UserDefaults.standard.bool(forKey: pendingKey) }

    /// Whether anything is left to remove.
    nonisolated static func hasData(in root: URL) -> Bool {
        folders(in: root).contains { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Makes WebKit the engine (now and for sites that had Chromium) and removes Chromium's data: at once when this
    /// launch doesn't run Chromium, otherwise at the next launch. Returns whether it is already gone.
    @discardableResult
    static func remove(state: BrowserState, running: Bool = BrowserRuntime.runs(.chromium), root: URL = root) -> Bool {
        state.browserPreferences.preferredEngine = .webkit
        state.browserPreferences.siteEngines = state.browserPreferences.siteEngines?.filter { $0.value != BrowserEngine.chromium.rawValue }
        state.browserPreferences.siteEngineLists = state.browserPreferences.siteEngineLists?.filter { $0.value != BrowserEngine.chromium.rawValue }
        state.saveNow()
        EngineCookieSync.forgetChromium()
        guard !running else {
            if !WebProfiles.isTestMode { UserDefaults.standard.set(true, forKey: pendingKey) }
            return false
        }
        delete(in: root)
        return true
    }

    /// At launch, when Chromium won't run: finishes a removal chosen while it was running.
    static func applyPendingAtLaunch() {
        guard isPending, !BrowserRuntime.runs(.chromium) else { return }
        delete(in: root)
        UserDefaults.standard.removeObject(forKey: pendingKey)
    }

    private static func delete(in root: URL) {
        for folder in folders(in: root) where FileManager.default.fileExists(atPath: folder.path) {
            do { try FileManager.default.removeItem(at: folder) }
            catch { NSLog("Ikago: couldn't remove Chromium's folder %@: %@", folder.lastPathComponent, error.localizedDescription) }
        }
    }
}
