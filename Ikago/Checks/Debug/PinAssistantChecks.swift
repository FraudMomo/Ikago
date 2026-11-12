#if DEBUG
import AppKit

/// Pin presentation survives moves/restores; integrated editors exercise real native clicks.
@MainActor
enum PinAssistantChecks {
    static func run(_ browser: BrowserWindowController) async {
        let state = browser.state, saved = state.snapshot(), size = browser.window?.contentView?.bounds.size
        var failures = 0
        func check(_ value: Bool, _ label: String) {
            if !value { failures += 1 }
            print("IKTEST pinassistant \(value ? "PASS" : "FAIL") \(label)")
        }
        func settle() async { try? await Task.sleep(for: .milliseconds(350)) }
        defer {
            browser.chrome.editFolderID = nil; browser.chrome.showPageAssistant = false
            browser.chrome.endTabDrag(); state.apply(saved)
            if let size { browser.window?.setContentSize(size) }
        }
        browser.dismissCommandPalette()
        state.tabLayout = .vertical; state.sidebarVisible = true; state.useGlass = false
        let pin = state.newTab(url: InternalPage.history.url)!
        let peer = state.newTab(url: InternalPage.bookmarks.url)!
        state.togglePin(pin.id)
        check(pin.pinned && pin.pinAsRow && !state.sidebarGridPinnedTabs.contains { $0.id == pin.id }, "Pin Tab creates a standalone row")
        state.movePin(pin.id, intoGrid: true)
        check(state.sidebarGridPinnedTabs.contains { $0.id == pin.id }, "dropping into the grid makes a tile")
        state.reorderTab(pin.id, relativeTo: peer.id, after: false)
        check(pin.pinned && pin.pinAsRow, "dragging a tile into the list preserves its pinned identity")
        state.movePin(peer.id, intoGrid: true)
        state.reorderTab(pin.id, relativeTo: peer.id, after: true)
        check(pin.pinned && !pin.pinAsRow, "dropping beside a grid tile inherits its presentation")
        state.moveTabToListEnd(pin.id)
        check(pin.pinned && pin.pinAsRow, "dropping at the list end makes a standalone pin")
        let restored = BrowserState(store: SessionStore(directory: SessionStore.testDirectory.appending(path: "PinPresentation")))
        defer { restored.saveTask?.cancel() }
        restored.apply(state.snapshot())
        check(restored.tab(pin.id)?.pinAsRow == true && restored.tab(peer.id)?.pinAsRow == false,
              "row and grid placement both survive a session round trip")
        state.togglePin(pin.id)
        check(!pin.pinned, "the same pin action unpins the row")

        state.chromeLayout.place(.assistant, in: .sidebarTop)
        state.browserPreferences.pageIntelligence = false
        browser.togglePageAssistant()
        check(!browser.chrome.showPageAssistant && !state.visibleChromeItems(state.chromeLayout.sidebarTop).contains(.assistant),
              "disabled page assistance cannot open and has no toolbar slot")
        state.browserPreferences.pageIntelligence = true
        browser.togglePageAssistant(); await settle()
        check(browser.chrome.showPageAssistant && state.visibleChromeItems(state.chromeLayout.sidebarTop).contains(.assistant),
              "enabling assistance restores its customized placement")
        state.browserPreferences.pageIntelligence = false; await settle()
        check(!browser.chrome.showPageAssistant, "disabling assistance closes an already-open panel")
        state.browserPreferences.pageIntelligence = true
        browser.togglePageAssistant(); await settle()

        guard let window = browser.window, let root = window.contentView else { check(false, "browser window exists"); return }
        window.makeKeyAndOrderFront(nil)
        func click(_ key: String, nearEdge: Bool = false) -> Bool {
            guard let frame = LayoutChecks.frames[key] else { return false }
            let top = NSPoint(x: nearEdge ? frame.minX + 4 : frame.midX, y: frame.midY)
            let local = NSPoint(x: top.x, y: root.isFlipped ? top.y : root.bounds.height - top.y)
            let point = root.convert(local, to: nil)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                if let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, eventNumber: 1, clickCount: 1, pressure: 1) { window.sendEvent(event) }
            }
            return true
        }
        check(click("assistant-close", nearEdge: true), "page assistance exposes its full close target")
        await settle()
        check(!browser.chrome.showPageAssistant, "clicking beside the close glyph dismisses assistance")

        state.colorMode = .light
        let folder = state.createFolder(named: "Creative projects")
        browser.customizeFolder(folder.id); await settle()
        if let frame = LayoutChecks.frames["group-appearance-editor"] {
            check(abs(frame.width - 330) < 1 && frame.height < 560, "group editor stays compact with no oversized menu")
        } else { check(false, "group editor has a rendered frame") }
        _ = click("group-editor-icon-star.fill"); await settle()
        _ = click("group-editor-color-blue"); await settle()
        check(state.folders.first { $0.id == folder.id }?.icon == nil, "preview changes remain a draft")
        TestDriver.snapshot(window, to: "/private/tmp/ikago-group-editor-light.png")
        _ = click("group-editor-done", nearEdge: true); await settle()
        let updated = state.folders.first { $0.id == folder.id }
        check(updated?.icon == "star.fill" && updated?.tag == "blue" && browser.chrome.editFolderID == nil,
              "Done applies icon and color together through the full button target")
        state.colorMode = .dark
        window.setContentSize(NSSize(width: 700, height: 600))
        browser.customizeFolder(folder.id); await settle()
        if let frame = LayoutChecks.frames["group-appearance-editor"] {
            check(frame.minX >= 0 && frame.minY >= 0 && frame.maxX <= root.bounds.width && frame.maxY <= root.bounds.height,
                  "editor fits a smaller window")
        }
        TestDriver.snapshot(window, to: "/private/tmp/ikago-group-editor-dark.png")
        _ = click("group-editor-icon-heart.fill"); await settle()
        _ = click("group-editor-cancel"); await settle()
        check(state.folders.first { $0.id == folder.id }?.icon == "star.fill" && browser.chrome.editFolderID == nil,
              "Cancel discards the preview")
        print("IKTEST pinassistantchecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }
}
#endif
