#if DEBUG
import SwiftUI
import WebKit

/// Website access for extensions on WebKit: a new extension asks and doesn't run until allowed; Always Allow, One Day,
/// Don't Allow and Every Website reach the page; the first-visit card offers it once per website.
@MainActor
enum ExtensionAccessChecks {
    static func run(_ c: BrowserWindowController, base: String) async {
        guard WebProfiles.isTestMode else { return }
        var failures = 0
        func check(_ value: Bool, _ title: String) {
            if !value { failures += 1 }
            print("IKTEST extensionaccess \(value ? "PASS" : "FAIL") \(title)")
        }
        let manager = ExtensionManager.shared, access = ExtensionAccess.shared
        let id = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaab"
        let folder = SessionStore.testDirectory.appending(path: "AccessFixture-\(UUID())")
        defer { manager.remove(id) }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let manifest = #"{"manifest_version":3,"name":"Marker","version":"1.0","host_permissions":["<all_urls>"],"content_scripts":[{"matches":["<all_urls>"],"js":["mark.js"],"run_at":"document_start"}]}"#
        try? Data(manifest.utf8).write(to: folder.appending(path: "manifest.json"))
        try? Data("document.documentElement.dataset.marker = '1'".utf8).write(to: folder.appending(path: "mark.js"))
        _ = try? await manager.install(unpackedAt: folder, id: id, fromWebStore: false, approve: false)
        check(access.entry(id).everySite == false, "a new extension asks on each website")

        func marked() async -> Bool {
            c.activeController?.page?.reload()
            try? await Task.sleep(for: .milliseconds(150))
            for _ in 0..<100 where c.state.activeTab?.isLoading != false { try? await Task.sleep(for: .milliseconds(20)) }
            try? await Task.sleep(for: .milliseconds(150))
            return (try? await c.activeController?.page?.evaluate("document.documentElement.dataset.marker || ''")) as? String == "1"
        }
        c.chrome.extensionAccessOffer = nil
        c.open(base + "/?access", inNewTab: true)
        for _ in 0..<150 where c.state.activeTab?.isLoading != false || c.activeController?.page == nil { try? await Task.sleep(for: .milliseconds(20)) }
        for _ in 0..<40 where c.chrome.extensionAccessOffer == nil { try? await Task.sleep(for: .milliseconds(50)) }
        let site = ExtensionAccess.site(URL(string: base)) ?? ""
        check(c.chrome.extensionAccessOffer?.site == site && c.chrome.extensionAccessOffer?.extensions.map(\.key) == [id],
              "the first visit offers the extension for \(site)")
        let first = (try? await c.activeController?.page?.evaluate("document.documentElement.dataset.marker || ''")) as? String
        check(first == "", "it doesn't run before it is allowed")
        access.choose(.always, key: id, site: site)
        check(await marked(), "Always Allow lets it run")
        access.choose(.never, key: id, site: site)
        check(await !marked(), "Don't Allow keeps it off")
        access.choose(.oneDay, key: id, site: site)
        if case .oneDay(let date) = access.status(id, site: site) { check(date > .now.addingTimeInterval(86_000), "one day lasts a day") }
        else { check(false, "one day lasts a day") }
        check(await marked(), "Allow for One Day lets it run")
        access.forget(site: site, key: id)
        let offAgain = await marked()
        check(access.status(id, site: site) == .ask && !offAgain, "Ask Next Time takes it off again")
        access.choose(.everySite, key: id, site: site)
        let everywhere = await marked()
        check(access.entry(id).everySite && everywhere, "Every Website lets it run everywhere")
        if let offer = c.chrome.extensionAccessOffer { ExtensionAccessPresenter.shared.notNow(offer, in: c.chrome) }
        print("IKTEST extensionaccesschecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
        guard let dir = DebugEnvironment.value("IKAGO_SHOTS"), let window = c.window, let content = window.contentView else { return }
        // Pictures: the first-visit card, the site card's row, and the Settings details.
        access.forget(site: site, key: id)
        access.setEverySite(false, key: id)
        c.open(base + "/?access-shot", inNewTab: true)
        for _ in 0..<60 where c.chrome.extensionAccessOffer == nil { try? await Task.sleep(for: .milliseconds(50)) }
        try? await Task.sleep(for: .milliseconds(600))
        print("IKTEST shot accesscard \(PeekShot.measure(content, window: window, save: dir + "/accesscard.png"))")
        c.chrome.extensionAccessOffer = nil
        access.choose(.oneDay, key: id, site: site)
        c.chrome.siteInfoAnchor = CGPoint(x: 220, y: 80)
        c.chrome.showSiteInfo = true
        try? await Task.sleep(for: .milliseconds(900))
        print("IKTEST shot accesssitecard \(PeekShot.measure(content, window: window, save: dir + "/accesssitecard.png"))")
        c.chrome.showSiteInfo = false
        access.choose(.never, key: id, site: "example.com")
        if let descriptor = manager.accessDescriptors.first(where: { $0.key == id }) {
            await TestDriver.render(ExtensionAccessDetails(ext: descriptor).padding(20).frame(width: 640, alignment: .leading)
                .background(Color(nsColor: .windowBackgroundColor)), size: NSSize(width: 640, height: 300), to: dir + "/accessdetails.png")
        }
    }
}
#endif
