import AppKit
import WebKit

/// Website notifications and Save Page on Chromium: the page-world shim talks to Ikago and is told back, a page can't
/// make Ikago deliver by itself (Ikago decides), and a page saves as MHTML and PDF.
@MainActor
enum CEFPageToolChecks {
    @MainActor private final class Recorder: WebTabDelegate {
        var messages: [[String: Any]] = []
        weak var tab: CEFWebTab?
        func webTab(_ page: WebTab, notification json: String) {
            guard let data = json.data(using: .utf8), let message = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
            messages.append(message)
            // What the site's saved choice would answer: asked for permission, it is granted.
            if message["t"] as? String == "request" {
                page.sendNotificationMessage(["t": "request", "id": message["id"] as? Int ?? 0, "value": "granted"])
            }
        }
        func webTab(_ page: WebTab, didChangeTitle title: String) {}
        func webTab(_ page: WebTab, didChangeURL url: String) {}
        func webTab(_ page: WebTab, didCommit url: String) {}
        func webTab(_ page: WebTab, didChangeProgress progress: Double) {}
        func webTab(_ page: WebTab, didChangeLoading isLoading: Bool, canGoBack: Bool, canGoForward: Bool) {}
        func webTab(_ page: WebTab, didFailLoad message: String, url: String?) {}
        func webTab(_ page: WebTab, blocksUnsafeNavigation url: URL) -> Bool { false }
        func webTab(_ page: WebTab, handsOff url: URL, method: String) -> Bool { false }
        func webTab(_ page: WebTab, usesOtherEngine url: URL) -> Bool { false }
        func webTab(_ page: WebTab, peeks url: URL, trigger: PeekTrigger) -> Bool { false }
        func webTab(_ page: WebTab, willUpgradeToHTTPS url: URL) {}
        func webTab(_ page: WebTab, mayDownload url: URL?) async -> Bool { false }
        func webTab(_ page: WebTab, didFindFavicon url: URL?) {}
        func webTab(_ page: WebTab, didChangeThemeColor color: NSColor?) {}
        func webTab(_ page: WebTab, didChangeSecureContent secure: Bool) {}
        func webTab(_ page: WebTab, popupWith configuration: WKWebViewConfiguration, url: String, background: Bool) -> WKWebView? { nil }
        func webTab(_ page: WebTab, adoptCEFPopup child: CEFWebTab, url: String, background: Bool) -> Bool { false }
        func webTab(_ page: WebTab, navigateToExtension url: String) {}
        func webTab(_ page: WebTab, openInNewTab url: String, background: Bool) {}
        func webTab(_ page: WebTab, requestsPermission request: PermissionRequest) { request.resolve(.deny) }
        func webTab(_ page: WebTab, didFind result: FindResult) {}
        func webTab(_ page: WebTab, didChangeMedia audible: Bool, camera: WKMediaCaptureState, microphone: WKMediaCaptureState) {}
        func webTab(_ page: WebTab, didChangePlayback playback: MediaPlaybackState) {}
        func webTabDidClose(_ page: WebTab) {}
        func webTab(_ page: WebTab, didDropFiles urls: [URL]) {}
        func webTab(_ page: WebTab, didHoverLink url: String?) {}
    }

    static func run(url: String, window: NSWindow) async throws {
        print("CEF_SMOKE_STAGE pagetools")
        let recorder = Recorder()
        let tab = try CEFWebTab(profileID: "Smoke")
        defer { tab.tearDown() }
        tab.delegate = recorder
        let previous = window.contentView
        window.contentView = tab.page
        defer { window.contentView = previous }
        try await wait { tab.page.ready }
        let before = tab.documentGeneration
        tab.load(url)
        try await wait { tab.documentGeneration >= before + 2 && !tab.page.loading }

        func page(_ expression: String) async throws -> Any? {
            let result = try await CEFSmoke.method(tab.page, "Runtime.evaluate", ["expression": expression, "returnByValue": true, "awaitPromise": true])
            return (result["result"] as? [String: Any])?["value"]
        }
        // The shim goes in after the page's isolated state script (observePageState), not with the load itself.
        do {
            try await wait { (try? await page("typeof Notification === 'function' && Notification.__ikago === true")) as? Bool == true }
        } catch { throw CEFError.script("The page has no notification shim.") }
        try await wait { recorder.messages.contains { $0["t"] as? String == "permission" } }
        tab.sendNotificationMessage(["t": "permission", "value": "granted"])
        try await wait { (try? await page("Notification.permission")) as? String == "granted" }
        let asked = try await page("Notification.requestPermission()") as? String
        guard asked == "granted" else { throw CEFError.script("requestPermission didn't resolve with Ikago's answer (\(asked ?? "nil")).") }
        _ = try await page("window.__clicked = 0; window.__n = new Notification('Deployed', {body: 'Done', tag: 'ci'}); window.__n.onclick = () => { window.__clicked += 1 }; true")
        try await wait { recorder.messages.contains { $0["t"] as? String == "show" && $0["title"] as? String == "Deployed" && $0["body"] as? String == "Done" } }
        let id = recorder.messages.last { $0["t"] as? String == "show" }?["id"] as? Int ?? 0
        tab.sendNotificationMessage(["t": "event", "id": id, "name": "click"])
        try await wait { (try? await page("window.__clicked")) as? Int == 1 }
        print("CEF_PAGETOOLS_STAGE notifications")

        let folder = FileManager.default.temporaryDirectory.appending(path: "IkagoCEFPageTools-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let archive = folder.appending(path: "page.mhtml"), pdf = folder.appending(path: "page.pdf")
        try await tab.savePage(as: .archive, to: archive)
        try await tab.savePage(as: .pdf, to: pdf)
        guard let mhtml = try? Data(contentsOf: archive), String(decoding: mhtml.prefix(200), as: UTF8.self).contains("MIME-Version") else {
            throw CEFError.script("The MHTML archive is missing or malformed.")
        }
        guard (try? Data(contentsOf: pdf))?.starts(with: Data("%PDF".utf8)) == true else { throw CEFError.script("The PDF is missing or malformed.") }
        // The rest of Save Page: HTML, text, one long PDF page, and images of the whole page and the visible area.
        let html = String(decoding: try await tab.exportPage(.html), as: UTF8.self)
        guard html.lowercased().contains("<html") else { throw CEFError.script("The HTML is missing.") }
        guard !(try await tab.exportPage(.text)).isEmpty else { throw CEFError.script("The text is missing.") }
        guard (try await tab.exportPage(.longPDF)).starts(with: Data("%PDF".utf8)) else { throw CEFError.script("The long PDF is missing.") }
        guard NSImage(data: try await tab.exportPage(.fullPNG)) != nil,
              (try await tab.exportPage(.visibleJPEG)).starts(with: Data([0xFF, 0xD8])) else {
            throw CEFError.script("The page images are missing.")
        }
        print("CEF_PAGETOOLS_OK notifications mhtml pdf html text longpdf images")
    }

    private static func wait(_ predicate: @MainActor () async -> Bool) async throws {
        try await CEFWait.until("Timed out waiting for the page tools fixture.") { await predicate() }
    }
}
