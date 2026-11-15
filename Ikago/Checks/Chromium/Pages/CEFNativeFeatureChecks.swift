import AppKit
import IKCEFBridge

@MainActor
enum CEFNativeFeatureChecks {
    private static let deepFind = """
    function find(root, selector) {
      const direct = root.querySelector(selector); if (direct) return direct;
      for (const e of root.querySelectorAll('*')) if (e.shadowRoot) { const found = find(e.shadowRoot, selector); if(found) return found; }
      return null;
    }
    """
    static func run(browser: IKCEFPage, profile: String, url: String) async throws {
        print("CEF_SMOKE_STAGE security-native")
        let security = IKCEFSecurity.snapshot(forProfile: profile)
        print("CEF_SECURITY_SNAPSHOT \(security)")
        try await CEFSafeBrowsingProbe.run(profile: profile)
        try CEFSecurityPreferenceChecks.run(profile: profile)
        print("CEF_SAFE_BROWSING_PREF available=\(security["safeBrowsingAvailable"] ?? false) enabled=\(security["safeBrowsingEnabled"] ?? false)")
        let target = URL(string: url)!.host == "127.0.0.1" ? url.replacingOccurrences(of: "127.0.0.1", with: "localhost") : url
        let quoted = String(data: try JSONSerialization.data(withJSONObject: [target]), encoding: .utf8)!
        let fetch = "fetch((\(quoted))[0] + '?trackerprobe', {cache:'no-store'}).then(()=>true,()=>false)"
        IKCEFSecurity.configure(["trackers": true, "cookies": true, "safeBrowsing": true, "domains": ["localhost"]])
        guard try await value(browser, fetch, promise: true) as? Bool == false else { throw CEFError.script("Tracker request was not blocked.") }
        IKCEFSecurity.configure(["trackers": false, "cookies": true, "safeBrowsing": true, "domains": ["localhost"]])
        guard try await value(browser, fetch, promise: true) as? Bool == true else { throw CEFError.script("Tracker positive control failed.") }
        IKCEFSecurity.configure(["trackers": true, "cookies": true, "safeBrowsing": true, "domains": BrowserSecurity.trackerDomains])
        try await CEFCertificateCheck.run(profile: profile)
        try await checkPrivateTools()
        try await CEFCaptureChecks.run(browser, url: url)
        print("CEF_SMOKE_STAGE devtools")
        browser.setDeveloperToolsEnabled(true)
        browser.inspect(at: NSPoint(x: 40, y: 40))
        try await wait { browser.devToolsVisible }
        browser.setDeveloperToolsEnabled(false)
        try await wait { !browser.devToolsVisible }
        browser.toggleDevTools()
        guard !browser.devToolsVisible else { throw CEFError.script("Disabled DevTools opened.") }
        print("CEF_SMOKE_STAGE native-extensions")
        let extensionDirectory = CEFSessions.root.appending(path: "FixtureExtension", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: extensionDirectory, withIntermediateDirectories: true)
        let manifest: [String: Any] = ["manifest_version": 3, "name": "Ikago Fixture", "version": CommandLine.arguments.contains("--cef-smoke-read") ? "1.1" : "1.0",
            "permissions": ["storage", "tabs", "scripting"], "host_permissions": ["http://127.0.0.1/*"],
            "background": ["service_worker": "background.js"],
            "action": ["default_title": "Ikago Fixture Action", "default_popup": "popup.html"],
            "content_scripts": [["matches": ["http://127.0.0.1/*"], "js": ["content.js"]]]]
        try JSONSerialization.data(withJSONObject: manifest).write(to: extensionDirectory.appending(path: "manifest.json"))
        try Data("document.documentElement.dataset.ikagoExtensionFixture = 'active'; document.documentElement.dataset.ikagoExtensionVersion = chrome.runtime.getManifest().version; chrome.storage.local.get('fixture', data => {document.documentElement.dataset.ikagoExtensionStorage = data.fixture || 'missing'; chrome.storage.local.set({fixture:'persisted'}, () => {document.documentElement.dataset.ikagoExtensionSaved='yes';});});".utf8)
            .write(to: extensionDirectory.appending(path: "content.js"))
        try CEFExtensionAPIChecks.writeFixture(in: extensionDirectory)
        _ = try IKCEFNativeTools.openExtensions(forProfile: profile)
        var manager: IKCEFPage?
        try await wait {
            for item in IKCEFNativeTools.windows() {
                if (item["url"] as? String)?.hasPrefix("chrome://extensions") == true, item["loading"] as? Bool == false,
                   let id = item["id"] as? Int { manager = IKCEFNativeTools.hiddenPage(forWindow: id); return manager != nil }
            }
            return false
        }
        print("CEF_EXTENSION_MANAGER_READY")
        guard let manager else { throw CEFError.noResult }
        try await waitForValue(manager, "(() => { \(deepFind) return !!find(document,'#devMode'); })()")
        print("CEF_EXTENSION_DEV_MODE_READY")
        _ = try await value(manager, "(() => { \(deepFind) const t=find(document,'#devMode'); if(!t.checked)t.click(); return true; })()", gesture: true)
        try await Task.sleep(for: .milliseconds(300))
        let reading = CommandLine.arguments.contains("--cef-smoke-read")
        if !reading {
            guard try await value(manager, "(() => { \(deepFind) const b=find(document,'#loadUnpacked'); if(!b)return false; b.click(); return true; })()", gesture: true) as? Bool == true else {
                throw CEFError.script("Chromium’s Load Unpacked control was unavailable.")
            }
        }
        print("CEF_EXTENSION_LOAD_REQUESTED")
        try await waitForValue(manager, "(() => { \(deepFind) const item=find(document,'extensions-item'); return !!item && item.shadowRoot.textContent.includes('Ikago Fixture'); })()")
        print("CEF_EXTENSION_CARD_FOUND")
        browser.reloadIgnoringCache(false)
        try await waitForValue(browser, "document.documentElement.dataset.ikagoExtensionFixture === 'active'")
        try await waitForValue(browser, "document.documentElement.dataset.ikagoExtensionSaved === 'yes'")
        if reading { try await waitForValue(browser, "document.documentElement.dataset.ikagoExtensionStorage === 'persisted'") }
        try await CEFExtensionLifecycleChecks.run(manager: manager, browser: browser, directory: extensionDirectory)
        try await CEFExtensionAPIChecks.run(browser, profile: profile, url: url)
        IKCEFNativeTools.closeAll()
        print("CEF_NATIVE_FEATURES_OK tracker-toggle cookie-policy DevTools extension-install content-script")
    }
    private static func checkPrivateTools() async throws {
        let id = "Private-NativeToolFixture"
        try CEFSessions.prepare(id)
        let page = try IKCEFPage.make(profile: id)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = page
        defer { page.close(); CEFSessions.forget(id); window.contentView = nil }
        try await wait { page.ready }
        var denied = false
        do { _ = try IKCEFNativeTools.openExtensions(forProfile: id) } catch { denied = true }
        guard denied else { throw CEFError.script("Native extension tools opened in a private profile.") }
        print("CEF_PRIVATE_NATIVE_TOOLS_DENIED_OK")
    }
    private static func value(_ page: IKCEFPage, _ expression: String, gesture: Bool = false, promise: Bool = false) async throws -> Any? {
        let result = try await CEFSmoke.method(page, "Runtime.evaluate", ["expression": expression, "returnByValue": true, "userGesture": gesture, "awaitPromise": promise])
        return (result["result"] as? [String: Any])?["value"]
    }
    private static func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<200 { if condition() { return }; try await Task.sleep(for: .milliseconds(100)) }
        throw CEFError.script("Native feature fixture timed out.")
    }
    private static func waitForValue(_ page: IKCEFPage, _ expression: String) async throws {
        for _ in 0..<100 {
            if (try? await value(page, expression)) as? Bool == true { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        let debug = try? await value(page, "(() => { \(deepFind) return {url:location.href, body:document.body.innerText.slice(0,1500), dev:!!find(document,'#devMode'), load:!!find(document,'#loadUnpacked'), item:!!find(document,'extensions-item'), error:find(document,'extensions-load-error')?.shadowRoot?.innerText, manager:find(document,'extensions-manager')?.items_?.map(x=>x.name)}; })()")
        print("CEF_EXTENSION_DEBUG \(String(describing: debug))")
        throw CEFError.script("Native extension fixture timed out: \(expression.prefix(90))")
    }
}
