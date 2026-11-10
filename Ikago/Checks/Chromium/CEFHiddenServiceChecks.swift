import AppKit
import IKCEFBridge

/// Everything Ikago does through hidden Chromium services, with no Chromium window on screen.
@MainActor
enum CEFHiddenServiceChecks {
    static func run(url: String) async throws {
        print("CEF_SMOKE_STAGE hidden-services")
        try await devTools(url: url)
        try await extensions()
        try await websiteData(url: url)
        try await foreignPages(url: url)
        try noVisibleChromiumWindows()
    }

    /// DevTools must stay hidden until Ikago has removed its frame and docked it.
    private static func devTools(url: String) async throws {
        try CEFSessions.prepare("Smoke")
        let page = try IKCEFPage.make(profile: "Smoke")
        defer { page.close() }
        let host = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
        host.contentView = page
        try await wait { page.ready }
        page.loadURL(url)
        try await wait { !page.loading }
        var tools: NSWindow?
        page.devToolsWindowHandler = { tools = $0 }
        page.setDeveloperToolsEnabled(true)
        page.toggleDevTools()
        try await wait { tools != nil }
        guard let tools, !tools.isVisible else { throw CEFError.script("DevTools appeared as a Chromium window.") }
        let wasTitled = tools.styleMask.contains(.titled)
        DevToolsDock.removeFrame(of: tools)
        guard !tools.styleMask.contains(.titled), !tools.isVisible else { throw CEFError.script("DevTools kept its Chromium frame.") }
        guard tools.identifier == ChromiumWindowGuard.dockedDevTools, tools.alphaValue == 1 else {
            throw CEFError.script("Docked DevTools isn't exempt from the window guard.")
        }
        // Every side tiles the host exactly: page, divider gap, bar, DevTools; nothing overlaps.
        let bounds = NSRect(x: 0, y: 0, width: 1000, height: 700)
        for side in DevToolsDock.Side.allCases {
            let f = DevToolsDock.frames(in: bounds, side: side, share: 0.4)
            let parts = [f.page, f.divider, f.bar, f.tools]
            let area = parts.reduce(0) { $0 + $1.width * $1.height }
            let overlaps = parts.indices.contains { i in parts.indices.contains { j in i < j && parts[i].intersects(parts[j]) } }
            guard abs(area - bounds.width * bounds.height) < 1, !overlaps, parts.allSatisfy({ bounds.contains($0) }),
                  f.bar.height == DevToolsBar.height, f.bar.maxY == f.tools.maxY + DevToolsBar.height else {
                throw CEFError.script("DevTools docked \(side.rawValue) doesn't tile the page area.")
            }
        }
        let squeezed = DevToolsDock.frames(in: bounds, side: .right, share: 0.99)
        guard squeezed.page.width >= DevToolsDock.minimumPage else { throw CEFError.script("DevTools squeezed the page away.") }
        page.setDeveloperToolsEnabled(false)
        try await wait { !page.devToolsVisible }
        print("CEF_DEVTOOLS_DOCK_OK hidden-until-docked frame-removed guard-exempt sides=4 wasTitled=\(wasTitled)")
    }

    private static func extensions() async throws {
        let profile = "ExtensionHost"
        let manager = ChromiumExtensions()
        defer { manager.shutDown() }
        let folder = CEFSessions.root.appending(path: "HostFixtureExtension", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let manifest: [String: Any] = ["manifest_version": 3, "name": "Ikago Host Fixture", "version": "2.0", "description": "Fixture",
                                       "action": ["default_popup": "popup.html"]]
        try JSONSerialization.data(withJSONObject: manifest).write(to: folder.appending(path: "manifest.json"))
        try Data("<!doctype html><title>Popup</title>".utf8).write(to: folder.appending(path: "popup.html"))
        await manager.refresh(profile: profile)
        try check(manager, manager.items.isEmpty, "A fresh profile listed extensions.")
        await manager.install(folder: folder, profile: profile)
        guard let item = manager.items.first(where: { $0.name == "Ikago Host Fixture" }) else {
            throw CEFError.script("Installing from a folder failed: \(manager.issue ?? "not listed")")
        }
        try check(manager, item.enabled && item.version == "2.0" && item.popup == "popup.html", "An installed extension had the wrong details.")
        await manager.setEnabled(item, enabled: false, profile: profile)
        try check(manager, manager.items.first?.enabled == false, "Disabling an extension failed.")
        await manager.setEnabled(item, enabled: true, profile: profile)
        try check(manager, manager.items.first?.enabled == true, "Enabling an extension failed.")
        await manager.remove(item, profile: profile)
        try check(manager, manager.items.isEmpty, "Removing an extension failed.")
        try noVisibleChromiumWindows()
        print("CEF_EXTENSION_MANAGEMENT_OK list install disable enable remove no-chromium-window")
    }

    private static func check(_ manager: ChromiumExtensions, _ condition: Bool, _ message: String) throws {
        guard condition else { throw CEFError.script("\(message) \(manager.issue ?? "")") }
    }

    /// Clearing removes cookies and storage, and leaves other Spaces alone.
    private static func websiteData(url: String) async throws {
        let profiles = ["CleanupA", "CleanupB"]
        var pages: [IKCEFPage] = []
        defer { pages.forEach { $0.close() } }
        let host = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
        for profile in profiles {
            try CEFSessions.prepare(profile)
            let page = try IKCEFPage.make(profile: profile)
            host.contentView?.addSubview(page)
            if host.contentView == nil { host.contentView = page }
            pages.append(page)
            try await wait { page.ready }
            page.loadURL(url)
            // `loading` can still be false before the navigation starts, and a commit cancels a running script,
            // so keep trying until the fixture page itself has loaded and accepted the data.
            let write = "location.protocol.startsWith('http') && document.readyState === 'complete' && (document.cookie='keep=1; max-age=3600', localStorage.setItem('keep', '1'), true)"
            var written = false
            for _ in 0..<50 where !written {
                let result = try? await HiddenChromiumPage.call(page, "Runtime.evaluate", ["expression": write, "returnByValue": true])
                written = (result?["result"] as? [String: Any])?["value"] as? Bool == true
                if !written { try await Task.sleep(for: .milliseconds(100)) }
            }
            guard written else { throw CEFError.script("The cleanup fixture never loaded.") }
        }
        func hasCookie(_ page: IKCEFPage) async throws -> Bool {
            page.reloadIgnoringCache(false)
            // A reload that commits late cancels the script, so try again once it has settled.
            for attempt in 1...5 {
                try await Task.sleep(for: .milliseconds(200))
                try await wait { !page.loading }
                do {
                    let result = try await HiddenChromiumPage.call(page, "Runtime.evaluate", ["expression": "document.cookie.includes('keep=1') && localStorage.getItem('keep') === '1'", "returnByValue": true])
                    return (result["result"] as? [String: Any])?["value"] as? Bool == true
                } catch where attempt < 5 { continue }
            }
            return false
        }
        guard try await hasCookie(pages[0]) else { throw CEFError.script("The cleanup fixture's cookie was not set.") }
        // No known URLs, and the cookie's origin lacks the fixture's port: only the profile's files can name it.
        // Chromium commits Local Storage to disk after a delay, so give it time first.
        try await Task.sleep(for: .seconds(8))
        try await ChromiumWebsiteData.clear(profile: profiles[0])
        let remaining = try await HiddenChromiumPage.call(pages[0], "Runtime.evaluate", ["expression": "document.cookie.includes('keep=1') || localStorage.getItem('keep') !== null", "returnByValue": true])
        guard (remaining["result"] as? [String: Any])?["value"] as? Bool == false else { throw CEFError.script("Clearing website data left data behind.") }
        guard try await hasCookie(pages[1]) else { throw CEFError.script("Clearing one Space's data affected another.") }
        print("CEF_WEBSITE_DATA_CLEAR_OK no-window cookies local-storage space-isolated")
    }

    /// A page Chromium opens by itself reaches Ikago's handler instead of becoming a Chromium window.
    private static func foreignPages(url: String) async throws {
        var received: [URL] = []
        IKCEFNativeTools.setForeignPageHandler { received.append($0) }
        defer { IKCEFNativeTools.setForeignPageHandler(nil) }
        try CEFSessions.prepare("Smoke")
        let target = URL(string: url)!
        let tool = try await HiddenChromiumPage.open { try IKCEFNativeTools.openPage(target, profile: "Smoke") }
        defer { tool.close() }
        _ = try? await tool.run("void window.open(\(String(data: try JSONEncoder().encode(url + "?handed-over"), encoding: .utf8)!), '_blank')")
        try await wait { !received.isEmpty }
        guard received.first?.absoluteString.hasSuffix("?handed-over") == true else { throw CEFError.script("A foreign page was not handed over.") }
        try noVisibleChromiumWindows()
        print("CEF_FOREIGN_PAGE_OK handed-to-ikago")
    }

    static func noVisibleChromiumWindows() throws {
        let visible = NSApp.windows.filter { $0.isVisible && ChromiumWindowGuard.isChromiumWindow($0) }
        guard visible.isEmpty else { throw CEFError.script("\(visible.count) Chromium window(s) were visible.") }
    }

    private static func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<300 { if condition() { return }; try await Task.sleep(for: .milliseconds(50)) }
        throw CEFError.script("A hidden service check timed out.")
    }
}
