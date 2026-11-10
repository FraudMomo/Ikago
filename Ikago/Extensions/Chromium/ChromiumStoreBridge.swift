import AppKit
import WebKit

/// "Add to Ikago" on the Chrome Web Store when Chromium is the engine. The store page can't install
/// anything by itself: Ikago sees the person's real click (a passive monitor, like the password key),
/// asks the isolated script whether it hit the button, downloads and verifies the package, and asks
/// before installing it into the tab's Space.
@MainActor
final class ChromiumStoreBridge {
    private weak var tab: CEFWebTab?
    private var context: Int?
    private var injectedGeneration = -1
    private var injecting = false
    private var monitor: Any?
    private var lastID: String?

    init(tab: CEFWebTab) { self.tab = tab }

    private var onStore: Bool { URL(string: tab?.currentURL ?? "")?.host == "chromewebstore.google.com" }

    func tearDown() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    /// After a commit, a finished load or an in-page navigation (the store is a single-page app).
    func pageChanged() {
        guard let tab, !tab.isTornDown, onStore else { return }
        installMonitor()
        if injectedGeneration == tab.documentGeneration, context != nil { return refreshStatus() }
        guard !injecting else { return }
        injecting = true
        Task { @MainActor in
            defer { injecting = false }
            for _ in 0..<10 {
                guard let tab = self.tab, !tab.isTornDown, onStore else { return }
                let generation = tab.documentGeneration
                do {
                    let tree = try await tab.devTools("Page.getFrameTree", [:], generation: generation)
                    guard let frame = (tree["frameTree"] as? [String: Any])?["frame"] as? [String: Any],
                          let frameID = frame["id"] as? String else { throw CEFError.noResult }
                    let world = try await tab.devTools("Page.createIsolatedWorld", ["frameId": frameID, "worldName": ChromiumStoreScript.world], generation: generation)
                    guard let id = world["executionContextId"] as? Int else { throw CEFError.noResult }
                    _ = try await tab.devTools("Runtime.evaluate", ["expression": ChromiumStoreScript.source, "contextId": id, "userGesture": false], generation: generation)
                    context = id
                    injectedGeneration = generation
                    lastID = nil
                    refreshStatus()
                    return
                } catch {
                    try? await Task.sleep(for: .milliseconds(300))
                }
            }
        }
    }

    /// Tells the page whether the extension it shows is already in this Space.
    private func refreshStatus() {
        guard let tab else { return }
        Task { @MainActor in
            guard let id = await call("function () { return window.__ikagoStore ? window.__ikagoStore.current() : null }") as? String,
                  WebStoreInstaller.isValidID(id) else { return }
            if ChromiumExtensions.shared.profile != tab.profileID { await ChromiumExtensions.shared.sync(profile: tab.profileID) }
            let installed = ChromiumExtensions.shared.items.contains { ChromiumExtensions.storeID(of: $0) == id }
            if lastID != id || installed { await set(id, installed ? "installed" : "none") }
            lastID = id
        }
    }

    private func installMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, let tab = self.tab, !tab.isTornDown, self.onStore, self.context != nil,
                      event.window === tab.page.window, event.clickCount == 1,
                      let hit = tab.page.window?.contentView?.hitTest(event.locationInWindow),
                      hit === tab.page || hit.isDescendant(of: tab.page) else { return }
                self.clicked(at: tab.page.convert(event.locationInWindow, from: nil), in: tab)
            }
            return event
        }
    }

    private func clicked(at point: NSPoint, in tab: CEFWebTab) {
        let zoom = pow(1.2, tab.zoomLevel)
        let x = point.x / zoom, y = (tab.page.bounds.height - tab.page.topInset - point.y) / zoom
        guard x >= 0, y >= 0 else { return }
        Task { @MainActor in
            guard let id = await call("function (x, y) { return window.__ikagoStore ? window.__ikagoStore.hit(x, y) : null }", [x, y]) as? String,
                  WebStoreInstaller.isValidID(id) else { return }
            await install(id, in: tab)
        }
    }

    private func install(_ id: String, in tab: CEFWebTab) async {
        let profile = tab.profileID
        do {
            let unpacked = try await WebStoreInstaller.download(id: id)  // CRX3 signatures verified
            defer { try? FileManager.default.removeItem(at: unpacked.deletingLastPathComponent()) }
            let preview = try await WKWebExtension(resourceBaseURL: unpacked)
            guard await ExtensionPrompts.confirmInstall(preview, in: tab.page.window, webKitNotes: false) else {
                return await set(id, "none")
            }
            await ChromiumExtensions.shared.install(unpacked: unpacked, storeID: id, profile: profile)
            if let issue = ChromiumExtensions.shared.issue { return await set(id, "error", "Couldn’t add it: \(issue)") }
            await set(id, "installed")
        } catch {
            await set(id, "error", "Couldn’t add it: \(error.localizedDescription)")
        }
    }

    private func set(_ id: String, _ state: String, _ reason: String = "") async {
        _ = await call("function (id, state, reason) { if (window.__ikagoStore) window.__ikagoStore.set(id, state, reason) }", [id, state, reason])
    }

    /// Calls into the isolated world with values as arguments, never as script text.
    private func call(_ function: String, _ arguments: [Any] = []) async -> Any? {
        guard let tab, let context, injectedGeneration == tab.documentGeneration else { return nil }
        let result = try? await tab.devTools("Runtime.callFunctionOn", [
            "functionDeclaration": function, "executionContextId": context,
            "arguments": arguments.map { ["value": $0] }, "returnByValue": true, "userGesture": false], generation: tab.documentGeneration)
        return (result?["result"] as? [String: Any])?["value"]
    }
}
