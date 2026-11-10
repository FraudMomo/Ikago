import Foundation

extension ExtensionManager {
    /// Catches up with Web Store extensions added, changed or removed on Chromium, then records this
    /// engine's own so Chromium gets them too. Runs after the window opens; new extensions reach new pages.
    func syncWithOtherEngine() async {
        let mine = Dictionary(records.filter { $0.fromWebStore && $0.appexPath == nil }.map { ($0.id, $0.enabled) }) { a, _ in a }
        let plan = ExtensionSync.plan(for: .webkit, installed: mine, entries: ExtensionSync.entries())
        for id in plan.remove { remove(id) }
        for id in plan.enable { await setEnabled(id, true) }
        for id in plan.disable { await setEnabled(id, false) }
        for id in plan.install {
            let folder: URL
            do { folder = try await WebStoreInstaller.download(id: id) } catch { continue }  // offline: next launch
            defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
            do {
                // Approved when it was added on Chromium.
                _ = try await install(unpackedAt: folder, id: id, fromWebStore: true, approve: false)
                if let entry = ExtensionSync.entries().first(where: { $0.id == id }), !entry.enabled { await setEnabled(id, false) }
            } catch {
                ExtensionSync.unsupported(id, on: .webkit, reason: error.localizedDescription)
                installIssue = nil
            }
        }
        let now = Dictionary(records.filter { $0.fromWebStore && $0.appexPath == nil }.map { ($0.id, $0.enabled) }) { a, _ in a }
        ExtensionSync.adopt(now)
    }
}
