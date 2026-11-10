import Foundation

extension ChromiumExtensions {
    /// Catches up this Space with Web Store extensions added, changed or removed on WebKit, then records
    /// this Space's own so WebKit gets them too. Also refreshes the list Settings shows.
    func sync(profile: String) async {
        await refresh(profile: profile)
        guard issue == nil, self.profile == profile else { return }
        var mine: [String: Item] = [:]
        for item in items { if let id = Self.storeID(of: item) { mine[id] = item } }
        let plan = ExtensionSync.plan(for: .chromium, installed: mine.mapValues(\.enabled), entries: ExtensionSync.entries())
        for id in plan.remove { if let item = mine[id] { await remove(item, profile: profile) } }
        for id in plan.enable { if let item = mine[id] { await setEnabled(item, enabled: true, profile: profile) } }
        for id in plan.disable { if let item = mine[id] { await setEnabled(item, enabled: false, profile: profile) } }
        for id in plan.install {
            await install(storeLink: id, profile: profile)
            guard let issue else {
                if let entry = ExtensionSync.entries().first(where: { $0.id == id }), !entry.enabled,
                   let item = items.first(where: { Self.storeID(of: $0) == id }) {
                    await setEnabled(item, enabled: false, profile: profile)
                }
                continue
            }
            // A download that failed (offline) is tried again next launch; anything else is unsupported here.
            if !issue.localizedCaseInsensitiveContains("internet"), !issue.localizedCaseInsensitiveContains("network"),
               !issue.localizedCaseInsensitiveContains("didn't return") {
                ExtensionSync.unsupported(id, on: .chromium, reason: issue)
            }
            self.issue = nil
        }
        var now: [String: Bool] = [:]
        for item in items { if let id = Self.storeID(of: item) { now[id] = item.enabled } }
        ExtensionSync.adopt(now)
    }
}
