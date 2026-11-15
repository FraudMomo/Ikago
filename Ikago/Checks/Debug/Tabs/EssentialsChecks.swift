#if DEBUG
import AppKit
import CryptoKit

@MainActor
enum EssentialsChecks {
    static func run(_ browser: BrowserWindowController) async {
        let state = browser.state, original = state.snapshot()
        var failures = 0
        func check(_ value: Bool, _ title: String) {
            print("IKTEST essentials \(value ? "PASS" : "FAIL") \(title)")
            if !value { failures += 1 }
        }
        defer { state.apply(original) }
        let pin = state.newTab(url: "https://saved-pin.invalid")!
        state.togglePin(pin.id)
        let controller = browser.content.ensureController(for: pin)!
        controller.startIfNeeded()
        pin.faviconURL = URL(string: "https://icons.invalid/custom.png")
        browser.closeTab(pin.id)
        try? await Task.sleep(for: .milliseconds(400))
        check(state.tab(pin.id) != nil && pin.pinned && pin.isHibernating && controller.page == nil,
              "closing a pin retains its identity and unloads its web view")
        check(state.activeTabID != pin.id && !state.closed.contains { $0.id == pin.id }, "unloaded pin leaves active panes and closed-tab history")
        state.select(pin.id)
        try? await Task.sleep(for: .milliseconds(400))
        check(controller.page != nil && !pin.isHibernating, "selecting a pin wakes the same tab")
        browser.closeTab(pin.id)
        try? await Task.sleep(for: .milliseconds(300))
        let restored = BrowserState(store: SessionStore(directory: SessionStore.testDirectory.appending(path: "IconRestore")))
        defer { restored.saveTask?.cancel() }
        restored.apply(state.snapshot())
        check(restored.tab(pin.id)?.faviconURL == pin.faviconURL && restored.tab(pin.id)?.isHibernating == true,
              "custom favicon and unloaded state survive session round trip")
        let tab = state.newTab(url: "https://saved-icon.invalid")!
        tab.faviconURL = pin.faviconURL
        state.addBookmark(tab)
        check(state.tab(tab.id) != nil && state.bookmarks.first { $0.url == tab.url }?.favicon == pin.faviconURL?.absoluteString,
              "saving a bookmark preserves the open tab and custom icon")
        state.move(tab.id, before: nil, pinned: true)
        state.move(tab.id, before: nil, pinned: false)
        check(!tab.pinned && tab.faviconURL == pin.faviconURL, "dragging a pin into open tabs unpins it and retains its icon")
        let iconURL = URL(string: "https://cached-icon.invalid/\(UUID()).png")!
        let key = SHA256.hash(data: Data(iconURL.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        let folder = SessionStore.testDirectory.appending(path: "Favicons")
        let file = folder.appending(path: key)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let image = NSImage(size: NSSize(width: 16, height: 16))
            image.lockFocus(); NSColor.red.setFill(); NSRect(x: 0, y: 0, width: 16, height: 16).fill(); image.unlockFocus()
            try image.tiffRepresentation!.write(to: file)
            try FileManager.default.setAttributes([.modificationDate: Date.distantPast], ofItemAtPath: file.path)
            let cached = await FaviconCache.shared.image(for: iconURL)
            check(cached != nil, "old disk icon loads offline without expiry or a live page")
        } catch { check(false, error.localizedDescription) }
        try? FileManager.default.removeItem(at: file)
        print("IKTEST essentialschecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }
}
#endif
