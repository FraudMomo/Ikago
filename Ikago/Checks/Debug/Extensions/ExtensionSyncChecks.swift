#if DEBUG
import Foundation

/// Web Store extensions stay the same on both engines (`ExtensionSync`), on a disposable test folder.
@MainActor
enum ExtensionSyncChecks {
    static func run(check: (Bool, String) -> Void) {
        let a = String(repeating: "a", count: 32), b = String(repeating: "b", count: 32)
        let c = String(repeating: "c", count: 32), d = String(repeating: "d", count: 32)
        try? FileManager.default.removeItem(at: ExtensionSync.file)
        defer { try? FileManager.default.removeItem(at: ExtensionSync.file) }

        // WebKit had a and b (b off) before syncing existed; Chromium gets both, b stays off.
        ExtensionSync.adopt([a: true, b: false])
        var plan = ExtensionSync.plan(for: .chromium, installed: [:], entries: ExtensionSync.entries())
        check(Set(plan.install) == [a, b], "extensions from one engine are installed on the other")
        check(plan.remove.isEmpty && plan.enable.isEmpty && plan.disable.isEmpty, "a fresh engine only installs")

        // On Chromium: turn b on, remove a, add c. WebKit follows; d can't run on WebKit and isn't retried.
        ExtensionSync.setEnabled(b, true)
        ExtensionSync.removed(a)
        ExtensionSync.added(c)
        ExtensionSync.added(d)
        ExtensionSync.unsupported(d, on: .webkit, reason: "Not supported")
        plan = ExtensionSync.plan(for: .webkit, installed: [a: true, b: false], entries: ExtensionSync.entries())
        check(plan.remove == [a], "removing on one engine removes on the other")
        check(plan.enable == [b], "turning one on carries over")
        check(plan.install == [c], "new ones carry over, unsupported ones aren't retried")
        check(ExtensionSync.plan(for: .chromium, installed: [b: true, c: true, d: true], entries: ExtensionSync.entries()).isEmpty,
              "an engine that matches has nothing to do")

        // Adding it again clears the unsupported mark; adopting never revives a removed one.
        ExtensionSync.added(d)
        check(ExtensionSync.plan(for: .webkit, installed: [b: true, c: true], entries: ExtensionSync.entries()).install == [d],
              "adding again retries an unsupported one")
        ExtensionSync.adopt([a: true])
        check(ExtensionSync.entries().first { $0.id == a }?.removed == true, "a removed extension isn't revived by the other engine's copy")
        ExtensionSync.added("not-an-id")
        check(!ExtensionSync.entries().contains { $0.id == "not-an-id" }, "only Web Store IDs sync")
        // uBlock Origin Lite comes by default, enabled, once; a removed default stays removed.
        let ubol = ExtensionSync.defaults[0]
        ExtensionSync.seedDefaults(testing: true)
        check(ExtensionSync.plan(for: .chromium, installed: [:], entries: ExtensionSync.entries()).install.contains(ubol),
              "uBlock Origin Lite is installed by default")
        ExtensionSync.removed(ubol)
        ExtensionSync.seedDefaults(testing: true)
        check(ExtensionSync.entries().first { $0.id == ubol }?.removed == true, "removing a default extension sticks")
        let raw = (try? Data(contentsOf: ExtensionSync.file)) ?? Data()
        check(SealedStorage.isSealed(raw), "the sync list is encrypted like other local data")
    }
}
#endif
