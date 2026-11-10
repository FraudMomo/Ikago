#if DEBUG
import Foundation

@MainActor
enum TabPlacementChecks {
    static func run() async {
        var failures = 0
        func check(_ value: Bool, _ title: String) {
            print("IKTEST tabplacement \(value ? "PASS" : "FAIL") \(title)")
            if !value { failures += 1 }
        }
        let root = FileManager.default.temporaryDirectory.appending(path: "IkagoTabPlacement-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SessionStore(directory: root), state = BrowserState(store: SessionStore(directory: root))
        check(state.newTabPosition == .bottom && state.linkTabPosition == .afterCurrent, "legacy defaults preserve bottom placement and links after current")
        let a = state.newTab(url: "https://a.example")!, b = state.newTab(url: "https://b.example")!, c = state.newTab(url: "https://c.example")!
        state.newTabPosition = .top
        let top = state.newTab(url: "https://top.example")!
        check(state.looseTabs.map(\.id) == [top.id, a.id, b.id, c.id], "newest-on-top inserts without reversing existing order")
        state.newTabPosition = .bottom
        let bottom = state.newTab(url: "https://bottom.example")!
        check(state.looseTabs.last?.id == bottom.id, "newest-on-bottom appends to loose tabs")
        for policy in LinkTabPosition.allCases {
            state.linkTabPosition = policy
            for placement in NewTabPosition.allCases {
                state.newTabPosition = placement
                let active = state.activeTabID
                let child = state.newTabFromLink(url: "https://child.example", opener: b, select: false)!
                let ids = state.looseTabs.map(\.id), index = ids.firstIndex(of: child.id)!, opener = ids.firstIndex(of: b.id)!
                switch policy {
                case .beforeCurrent: check(index + 1 == opener, "before-current link placement ignores default end")
                case .afterCurrent: check(index == opener + 1, "after-current link placement ignores default end")
                case .newTabPosition: check(placement == .top ? index == 0 : index == ids.count - 1, "link can follow the selected new-tab end")
                }
                check(state.activeTabID == active, "background link preserves active tab")
                state.closeTab(child.id, removingPin: true)
            }
        }
        let folder = state.createFolder(named: "Work", with: a.id)
        state.moveToFolder(c.id, folderID: folder.id)
        state.linkTabPosition = .beforeCurrent
        let grouped = state.newTabFromLink(url: "https://group.example", opener: c, select: false)!
        check(grouped.folderID == folder.id && state.tabs(in: folder).map(\.id) == [a.id, grouped.id, c.id], "relative links stay adjacent within their opener's group")
        state.linkTabPosition = .newTabPosition
        let loose = state.newTabFromLink(url: "https://loose.example", opener: a, select: false)!
        check(loose.folderID == nil, "same-as-new-tabs opens outside the current group")
        state.togglePin(b.id)
        state.linkTabPosition = .beforeCurrent
        let pinLink = state.newTabFromLink(url: "https://pin-link.example", opener: b, select: false)!
        check(b.pinned && !pinLink.pinned && state.pinnedTabs.map(\.id) == [b.id] && state.looseTabs.first?.id == pinLink.id,
              "links from pinned tabs stay unpinned at the start of regular tabs")
        let personal = state.activeSpaceID
        let other = state.createSpace(name: "Other", symbol: "star", isolated: true)
        let foreign = state.newTab(url: "https://other.example")!
        state.linkTabPosition = .afterCurrent
        let child = state.newTabFromLink(url: "https://profile.example", opener: a, select: false)!
        check(child.spaceID == personal && child.folderID == folder.id && state.activeSpaceID == other.id,
              "background opener keeps its own Space and profile")
        check(state.spaceTabs.map(\.id) == [foreign.id], "other Spaces retain their tab order")
        _ = state.newTabFromLink(url: "https://foreground.example", opener: a, select: true)
        check(state.activeSpaceID == personal, "foreground link selects its opener's Space")
        state.newTabPosition = .top; state.linkTabPosition = .newTabPosition
        state.saveNow()
        let restored = BrowserState(store: store)
        check(restored.newTabPosition == .top && restored.linkTabPosition == .newTabPosition && restored.tabs.map(\.saved) == state.tabs.map(\.saved),
              "placement preferences and manually arranged tabs survive restore")
        var json = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(state.snapshot()))) as? [String: Any] ?? [:]
        var browser = json["browser"] as? [String: Any] ?? [:]
        browser.removeValue(forKey: "newTabPosition"); browser.removeValue(forKey: "linkTabPosition"); json["browser"] = browser
        do {
            try store.save(JSONDecoder().decode(Session.self, from: JSONSerialization.data(withJSONObject: json)))
            let legacy = BrowserState(store: store)
            check(legacy.newTabPosition == .bottom && legacy.linkTabPosition == .afterCurrent, "older profiles restore with safe placement defaults")
        } catch { check(false, error.localizedDescription) }
        print("IKTEST tabplacementchecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }
}
#endif
