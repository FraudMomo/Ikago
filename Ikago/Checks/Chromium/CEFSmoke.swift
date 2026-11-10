import AppKit
import WebKit
import IKCEFBridge

/// Disposable integration fixture: no session, saved profile or browser UI.
@MainActor
enum CEFSmoke {
    /// Runs the whole suite on a disposable profile, with no visible window or Dock icon, then exits.
    static func runAndExit(_ app: NSApplication) -> Never {
        app.setActivationPolicy(.prohibited)
        let delegate = CEFSmokeTerminationDelegate()
        app.delegate = delegate
        BrowserRuntime.engine = .chromium
        BrowserRuntime.running = [.chromium]
        ChromiumWindowGuard.install()
        if let index = CommandLine.arguments.firstIndex(of: "--cef-smoke-root"), CommandLine.arguments.indices.contains(index + 1) {
            let root = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
            guard root.lastPathComponent.hasPrefix("ikago-cef-smoke-") else { exit(2) }
            CEFSessions.overrideRoot = root
        } else {
            CEFSessions.overrideRoot = FileManager.default.temporaryDirectory.appending(path: "ikago-cef-smoke-" + UUID().uuidString)
        }
        var status: Int32 = 1
        do {
            try CEFGoogleServices.prepare()
            try CEFSessions.clearScheduledData()
            guard let urlIndex = CommandLine.arguments.firstIndex(of: "--cef-smoke"),
                  CommandLine.arguments.indices.contains(urlIndex + 1) else { exit(2) }
            let url = CommandLine.arguments[urlIndex + 1]
            try IKCEFRuntime.start(withArgc: CommandLine.argc, argv: CommandLine.unsafeArgv, root: CEFSessions.root,
                                   helper: BrowserRuntime.helperExecutable, ready: {
                Task { @MainActor in
                    status = CommandLine.arguments.contains("--cef-smoke-audio") ? await CEFAudioProbe.run()
                        : CommandLine.arguments.contains("--cef-smoke-dump") ? await CEFPageDump.run(url: url) : await run(url: url)
                    app.terminate(nil)
                }
            })
            IKCEFRuntime.runMessageLoop()
            try IKCEFRuntime.shutdown()
            withExtendedLifetime(delegate) {}
            if !CommandLine.arguments.contains("--cef-smoke-root"), let root = CEFSessions.overrideRoot { try? FileManager.default.removeItem(at: root) }
            print("CEF_SMOKE_SHUTDOWN_OK")
            exit(status)
        } catch {
            print("CEF_SMOKE_FAILED \(error.localizedDescription)")
            exit(1)
        }
    }

    static func run(url: String) async -> Int32 {
        setvbuf(stdout, nil, _IOLBF, 0)
        var page: IKCEFPage?
        var popup: IKCEFPage?
        var extraPage: IKCEFPage?
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        do {
            print("CEF_SMOKE_STAGE prepare")
            try CEFGoogleServicesChecks.run()
            try CEFSessions.prepare("Smoke")
            let browser = try IKCEFPage.make(profile: "Smoke")
            page = browser
            window.contentView = browser
            print("CEF_SMOKE_STAGE browser-ready")
            try await until { browser.ready }
            var committed = false
            browser.eventHandler = { event, _ in print("CEF_SMOKE_EVENT \(event)"); if event == "commit" { committed = true } }
            browser.popupHandler = { child, _, _ in
                popup = child
                window.contentView?.addSubview(child)
                return true
            }
            print("CEF_SMOKE_STAGE navigation")
            browser.loadURL(url)
            try await until { committed && !browser.loading }
            print("CEF_SMOKE_STAGE scripts")
            let tree = try await method(browser, "Page.getFrameTree", [:])
            guard let frame = (tree["frameTree"] as? [String: Any])?["frame"] as? [String: Any],
                  let id = frame["id"] as? String else { throw CEFError.noResult }
            let world = try await method(browser, "Page.createIsolatedWorld", ["frameId": id, "worldName": "ikago-smoke"])
            guard let context = world["executionContextId"] as? Int else { throw CEFError.noResult }
            let result = try await method(browser, "Runtime.evaluate", [
                "contextId": context, "returnByValue": true,
                "expression": "({title:document.title, isolated:typeof window.pageSecret === 'undefined', text:document.body.innerText.includes('CEF fixture')})"
            ])
            guard let value = (result["result"] as? [String: Any])?["value"] as? [String: Any],
                  value["title"] as? String == "Ikago Chromium Fixture", value["isolated"] as? Bool == true,
                  value["text"] as? Bool == true else { throw CEFError.script("DOM or isolated-world fixture failed.") }
            print("CEF_SMOKE_STAGE persistence")
            let reading = CommandLine.arguments.contains("--cef-smoke-read")
            if !reading {
                let cookie = HTTPCookie(properties: [.domain: "127.0.0.1", .path: "/", .name: "cef-import", .value: "ok", .expires: Date().addingTimeInterval(3600)])!
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    IKCEFContexts.setCookie(cookie, sameSite: 1, profile: "Smoke") { error in
                        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                    }
                }
            }
            let expression = reading ? "localStorage.getItem('ikago-cef-storage') === 'persisted-fixture' && document.cookie.includes('cef-import=ok')" : "localStorage.setItem('ikago-cef-storage','persisted-fixture'); document.cookie.includes('cef-import=ok')"
            let storage = try await method(browser, "Runtime.evaluate", ["expression": expression, "contextId": context, "returnByValue": true])
            guard (storage["result"] as? [String: Any])?["value"] as? Bool == true else { throw CEFError.script("Cookie import or restart persistence failed.") }
            print("CEF_SMOKE_STAGE screenshot")
            let capture = try await method(browser, "Page.captureScreenshot", ["format": "png"])
            guard let encoded = capture["data"] as? String, let data = Data(base64Encoded: encoded),
                  NSImage(data: data) != nil else { throw CEFError.script("Screenshot fixture failed.") }
            try await CEFNativeFeatureChecks.run(browser: browser, profile: "Smoke", url: url)
            if !CommandLine.arguments.contains("--cef-smoke-read") {
                try await CEFPasswordChecks.run(url: url, window: window)
                try await CEFCookieIsolationChecks.run(url: url, window: window)
                window.contentView = browser
                try await CEFHiddenServiceChecks.run(url: url)
                print("CEF_SMOKE_STAGE cookie-sync")
                try await CEFCookieSyncChecks.run()
            }
            print("CEF_SMOKE_STAGE popup")
            _ = try await method(browser, "Runtime.evaluate", ["expression": "document.querySelector('button').click()", "userGesture": true])
            try await until { popup?.ready == true && popup?.loading == false }
            guard let popup else { throw CEFError.script("The popup was not adopted.") }
            let openerResult = try await method(popup, "Runtime.evaluate", ["expression": "Boolean(window.opener)", "returnByValue": true])
            guard (openerResult["result"] as? [String: Any])?["value"] as? Bool == true else { throw CEFError.script("Popup opener identity was lost.") }
            print("CEF_SMOKE_STAGE downloads")
            var downloaded = false
            let download = CEFSessions.root.appending(path: "download.txt")
            IKCEFDownloads.shared.destinationHandler = { _, _, _, _ in download.path }
            IKCEFDownloads.shared.eventHandler = { snapshot, _ in downloaded = snapshot["complete"] as? Bool ?? false }
            try? FileManager.default.removeItem(at: download)  // the restart launch shares this profile
            // Denied first: nothing may reach the disk or the download list.
            var asked = 0
            browser.downloadGateHandler = { _, _, reply in asked += 1; reply(false) }
            _ = try? await method(browser, "Runtime.evaluate", ["expression": "location.href='/download'", "userGesture": true])
            try await until { asked > 0 }
            try await Task.sleep(for: .milliseconds(500))
            guard !downloaded, !FileManager.default.fileExists(atPath: download.path) else { throw CEFError.script("A denied download was saved anyway.") }
            browser.downloadGateHandler = { _, _, reply in reply(true) }
            print("CEF_DOWNLOAD_GATE_OK denied-saved-nothing")
            // Chromium itself refuses a second scripted download from one page without a real click,
            // which is what stops download floods. A fresh page starts clean.
            committed = false
            browser.loadURL(url)
            try await until { committed && !browser.loading }
            _ = try? await method(browser, "Runtime.evaluate", ["expression": "location.href='/download'", "userGesture": true])
            try await until { downloaded }
            guard try Data(contentsOf: download).count == 4096 else { throw CEFError.script("Download bytes did not match.") }
            print("CEF_SMOKE_STAGE popup-self-close")
            // CEF intentionally permits script-opened and history-free tabs to
            // close themselves. An ordinary tab with history stays protected.
            committed = false
            browser.loadURL(url + "?close-history")
            try await until { committed && !browser.loading && browser.canGoBack }
            _ = try? await method(browser, "Runtime.evaluate", ["expression": "window.close()"])
            try await Task.sleep(for: .milliseconds(150))
            guard !browser.isClosed else { throw CEFError.script("An ordinary page closed its browser tab without approval.") }
            committed = false
            browser.goBack()
            try await until { committed && !browser.loading }
            _ = try? await method(popup, "Runtime.evaluate", ["expression": "window.close()"])
            try await until { popup.isClosed }
            print("CEF_POPUP_SELF_CLOSE_OK script-opened-popup")
            print("CEF_SMOKE_STAGE second-page")
            try CEFSessions.prepare("OtherSpace")
            let isolated = try IKCEFPage.make(profile: "OtherSpace")
            extraPage = isolated
            window.contentView?.addSubview(isolated)
            try await until { isolated.ready }
            var otherCommitted = false
            isolated.eventHandler = { name, _ in if name == "commit" { otherCommitted = true } }
            isolated.loadURL(url)
            try await until { otherCommitted && !isolated.loading }
            let otherStorage = try await method(isolated, "Runtime.evaluate", ["expression": "localStorage.getItem('ikago-cef-storage') === null && !document.cookie.includes('cef-import=ok') && document.documentElement.dataset.ikagoExtensionFixture === undefined", "returnByValue": true])
            guard (otherStorage["result"] as? [String: Any])?["value"] as? Bool == true else { throw CEFError.script("Website data crossed Spaces.") }
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in CEFSessions.flush { continuation.resume() } }
            isolated.close()
            popup.close()
            browser.close()
            print("CEF_SMOKE_STAGE local-file")
            let local = CEFSessions.root.appending(path: "local.html")
            try Data("<!doctype html><title>CEF local file</title><p>Local fixture</p>".utf8).write(to: local)
            let filePage = try IKCEFPage.make(profile: "Smoke")
            extraPage = filePage
            window.contentView?.addSubview(filePage)
            try await until { filePage.ready }
            var fileLoaded = false
            filePage.eventHandler = { name, payload in
                if name == "commit", (payload["value"] as? String)?.hasPrefix("file:") == true { fileLoaded = true }
            }
            filePage.loadURL(local.absoluteString)
            try await until { fileLoaded && !filePage.loading }
            let localResult = try await method(filePage, "Runtime.evaluate", ["expression": "document.title", "returnByValue": true])
            guard (localResult["result"] as? [String: Any])?["value"] as? String == "CEF local file" else { throw CEFError.script("Trusted local file navigation failed.") }
            filePage.close()
            print("CEF_SMOKE_STAGE SwiftUI-layouts")
            try await CEFShellChecks.run(url: url)
            print("CEF_SMOKE_STAGE site-engines")
            try await CEFSiteEngineChecks.run(url: url)
            print("CEF_SMOKE_STAGE WebKit-adapter")
            await BrowserSecurity.shared.prepare()
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            let webkit = WebKitTab(configuration: configuration)
            window.contentView = webkit.contentView
            webkit.load(url)
            try await until { webkit.currentURL == url && !webkit.isLoading }
            guard try await webkit.evaluate("document.title") as? String == "Ikago Chromium Fixture" else {
                throw CEFError.script("The preserved WebKit adapter could not load the fixture.")
            }
            webkit.tearDown()
            try CEFHiddenServiceChecks.noVisibleChromiumWindows()
            print("CEF_SMOKE_STAGE shutdown")
            try await until {
                IKCEFRuntime.canShutdown
            }
            print("CEF_SMOKE_OK navigation DOM isolated-world screenshot popup-opener downloads cookie-import space-isolation persistence local-file SwiftUI-layouts site-engines WebKit closed")
            return 0
        } catch {
            IKCEFNativeTools.closeAll()
            popup?.close(); extraPage?.close(); page?.close()
            print("CEF_SMOKE_FAILED \(error.localizedDescription)")
            if let log = try? String(contentsOf: CEFSessions.root.appending(path: "cef.log"), encoding: .utf8) { print(log.suffix(6000)) }
            try? await until { IKCEFRuntime.canShutdown }
            return 1
        }
    }
    private static func until(_ predicate: @MainActor () -> Bool) async throws {
        for _ in 0..<400 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw CEFError.script("The CEF fixture timed out.")
    }
    static func method(_ page: IKCEFPage, _ name: String, _ params: [String: Any]) async throws -> [String: Any] {
        let data: Data = try await withCheckedThrowingContinuation { continuation in
            page.devToolsMethod(name, parameters: params) { result, error in
                if let error { continuation.resume(throwing: error) }
                else if let result {
                    do { continuation.resume(returning: try JSONSerialization.data(withJSONObject: result)) }
                    catch { continuation.resume(throwing: error) }
                } else { continuation.resume(throwing: CEFError.noResult) }
            }
        }
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }
}

@MainActor
final class CEFSmokeTerminationDelegate: NSObject, IKCEFApplicationDelegate {
    func cefApplicationRequestsQuit() { BrowserRuntime.stopRunLoop() }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // CEF must route through its custom quit hook, without AppKit’s nested loop.
        print("CEF_SMOKE_FAILED unexpected AppKit termination path")
        BrowserRuntime.stopRunLoop()
        return .terminateCancel
    }
}
