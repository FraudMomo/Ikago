import AppKit
import IKCEFBridge

/// An extension's action popup, in Ikago's own popover. `ChromiumPopupLayer` runs first in the popup
/// so it sees the tab it was opened for through chrome.tabs.
@MainActor
final class ChromiumExtensionPopup: NSObject, NSPopoverDelegate {
    private static var current: ChromiumExtensionPopup?
    private let page: IKCEFPage
    private let popover = NSPopover()
    private var reload: (Bool) -> Void = { _ in }
    private var watching: Task<Void, Never>?

    private init(page: IKCEFPage) {
        self.page = page
        super.init()
    }

    /// `reload`: the popup asked to reload the tab it was opened for (true: bypassing the cache).
    static func show(_ item: ChromiumExtensions.Item, profile: String, tab: (url: String, title: String)?,
                     relativeTo anchor: NSView, reload: @escaping (Bool) -> Void = { _ in }) throws {
        guard let path = item.popup else { return }
        current?.popover.close()
        try CEFSessions.prepare(profile)
        let page = try IKCEFPage.make(profile: profile)
        // Registered before the popup's first navigation, so it runs before the popup's own scripts.
        if let tab { page.documentStartScript = ChromiumPopupLayer.source(url: tab.url, title: tab.title) }
        let popup = ChromiumExtensionPopup(page: page)
        popup.reload = reload
        current = popup
        let controller = NSViewController()
        controller.view = page
        popup.popover.contentViewController = controller
        popup.popover.contentSize = NSSize(width: 360, height: 480)
        popup.popover.behavior = .transient
        popup.popover.delegate = popup
        // A popup stays on its own extension; anything else it opens becomes a normal tab.
        let origin = "chrome-extension://\(item.id)/"
        page.navigationHandler = { url, _ in url.absoluteString.hasPrefix(origin) }
        page.popupHandler = { _, _, _ in false }
        popup.popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
        Task { await popup.load(origin + path) }
    }

    private func load(_ url: String) async {
        for _ in 0..<200 where !page.ready { try? await Task.sleep(for: .milliseconds(25)) }
        guard page.ready else { return }
        page.loadURL(url)
        watchRequests()
        try? await Task.sleep(for: .milliseconds(150))
        for _ in 0..<100 where page.loading { try? await Task.sleep(for: .milliseconds(50)) }
        guard let result = try? await HiddenChromiumPage.call(page, "Runtime.evaluate", [
            "expression": "JSON.stringify([document.documentElement.scrollWidth, document.documentElement.scrollHeight])",
            "returnByValue": true]),
              let text = (result["result"] as? [String: Any])?["value"] as? String,
              let size = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [Double], size.count == 2 else { return }
        popover.contentSize = NSSize(width: min(800, max(200, size[0])), height: min(600, max(120, size[1])))
    }

    /// Reloads the popup asked for (uBlock reloads the page after its filtering level changes).
    private func watchRequests() {
        watching = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(300))
                guard let self, !self.page.isClosed else { return }
                let result = try? await HiddenChromiumPage.call(self.page, "Runtime.evaluate", [
                    "expression": "globalThis.__ikagoRequests ? globalThis.__ikagoRequests.splice(0) : []", "returnByValue": true])
                for request in (result?["result"] as? [String: Any])?["value"] as? [String] ?? [] {
                    self.reload(request == "hard-reload")
                }
            }
        }
    }

    func popoverDidClose(_ notification: Notification) {
        watching?.cancel()
        page.close()
        if Self.current === self { Self.current = nil }
    }
}
