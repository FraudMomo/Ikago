#if DEBUG
import Foundation
import WebKit

@MainActor
enum ChromeExtensionChecks {
    static func run(_ browser: BrowserWindowController) async {
        var failures = 0
        func check(_ value: Bool, _ name: String) {
            print("IKTEST chrome \(value ? "PASS" : "FAIL") \(name)")
            if !value { failures += 1 }
        }
        let manager = ExtensionManager.shared
        let id = "pppppppppppppppppppppppppppppppp"
        let folder = FileManager.default.temporaryDirectory.appending(path: "IkagoChromeCheck-\(UUID().uuidString)")
        let previous = browser.state.activeTabID
        let website = browser.state.activeTab?.url ?? "https://example.com"
        var fixtureID: String?
        defer {
            if let fixtureID { browser.state.closeTab(fixtureID, removingPin: true) }
            manager.remove(id)
            try? FileManager.default.removeItem(at: folder)
            if let previous { browser.state.select(previous) }
        }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let manifest: [String: Any] = ["manifest_version": 3, "name": "Chrome origin fixture", "version": "1.0", "permissions": ["storage"],
                                           "options_ui": ["page": "options.html"], "chrome_url_overrides": ["newtab": "options.html"]]
            try JSONSerialization.data(withJSONObject: manifest).write(to: folder.appending(path: "manifest.json"))
            try Data("<!doctype html><title>Chrome origin fixture</title><h1>Extension page</h1>".utf8).write(to: folder.appending(path: "options.html"))
            _ = try await manager.install(unpackedAt: folder, id: id, fromWebStore: false, approve: false)
            guard let context = manager.contexts[id] else { throw ExtensionManager.error("Fixture did not load") }
            check(manager.context(for: URL(string: "chrome-extension://\(id)/options.html")!) === context, "Chrome URL resolves to the matching installed package")
            check(context.optionsPageURL != nil && context.overrideNewTabPageURL != nil, "options and new-tab pages are available")
            let url = "chrome-extension://\(id)/options.html"
            guard let controller = browser.openTabForExtension(url: url, active: true, pinned: false) else { throw ExtensionManager.error("No tab") }
            fixtureID = controller.tab.id
            try? await Task.sleep(for: .seconds(2))
            let result = try await controller.page?.webView.callAsyncJavaScript("return {id: chrome.runtime.id, url: chrome.runtime.getURL('options.html'), title: document.title}", arguments: [:], in: nil, contentWorld: .page) as? [String: Any]
            check(result?["id"] as? String == id && result?["url"] as? String == context.optionsPageURL?.absoluteString, "Chrome runtime APIs resolve the package ID and resource URL")
            check(controller.url(for: context)?.absoluteString == context.optionsPageURL?.absoluteString, "tab API resource URLs agree with runtime.getURL")
            check(result?["title"] as? String == "Chrome origin fixture", "extension resource page loads")
            let snapshot = browser.state.snapshot()
            try snapshot.validate()
            check(snapshot.tabs.contains { $0.url == url }, "extension tabs survive session serialization")
            controller.load(website)
            try? await Task.sleep(for: .seconds(1))
            check(controller.page?.currentURL.hasPrefix("http://") == true, "extension page can navigate to a normal website")
            _ = try? await controller.page?.callAsync("location.href = '\(url)'; return true")
            try? await Task.sleep(for: .seconds(1))
            check(controller.page.map { manager.canonicalURL($0.currentURL) == url } == true && controller.tab.loadError == nil, "normal website can navigate back to extension configuration")
            await manager.setEnabled(id, false)
            await manager.setEnabled(id, true)
            controller.load(url)
            try? await Task.sleep(for: .seconds(1))
            check(controller.page.map { manager.canonicalURL($0.currentURL) == url } == true && controller.tab.loadError == nil,
                  "stable extension session URL resolves after context recreation")
        } catch { check(false, error.localizedDescription) }
        print("IKTEST chromechecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }
}
#endif
