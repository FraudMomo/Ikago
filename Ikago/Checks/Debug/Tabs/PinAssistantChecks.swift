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
            browser.chrome.textPrompt?.finish(nil); browser.chrome.showNewSpace = false
            browser.chrome.endTabDrag(); state.apply(saved)
            if let size { browser.window?.setContentSize(size) }
        }
        browser.dismissCommandPalette()
        state.sidebarVisible = true; state.useGlass = false
        let pin = state.newTab(url: InternalPage.history.url)!
        let peer = state.newTab(url: InternalPage.bookmarks.url)!
        state.togglePin(pin.id)
        check(pin.pinned && pin.pinAsRow && !state.sidebarGridPinnedTabs.contains { $0.id == pin.id }, "Pin Tab creates a standalone row")
        state.movePin(pin.id, intoGrid: true)
        check(state.sidebarGridPinnedTabs.contains { $0.id == pin.id }, "dropping into the grid makes a tile")
        state.reorderTab(pin.id, relativeTo: peer.id, after: false)
        check(!pin.pinned && !pin.pinAsRow, "dragging a tile onto a normal tab unpins it")
        state.movePin(peer.id, intoGrid: true)
        state.reorderTab(pin.id, relativeTo: peer.id, after: true)
        check(pin.pinned && !pin.pinAsRow, "dropping beside a grid tile inherits its presentation")
        state.moveTabToListEnd(pin.id)
        check(!pin.pinned, "dropping at the normal list end unpins the tab")
        let placementFolder = state.createFolder(named: "Pin placement")
        state.movePin(pin.id, intoGrid: false, afterFolderID: placementFolder.id)
        check(pin.pinned && pin.pinAsRow && pin.pinAfterFolderID == placementFolder.id, "a standalone pin can sit below a group")
        let child = state.newTab(url: InternalPage.downloads.url)!
        state.moveToFolder(child.id, folderID: placementFolder.id)
        let sibling = state.newTab(url: InternalPage.notes.url, select: false)!
        state.moveToFolder(sibling.id, folderID: placementFolder.id)
        check(state.sidebarOrder.firstIndex { $0.id == pin.id }! > state.sidebarOrder.firstIndex { $0.id == child.id }!, "keyboard order follows a pin below its group")
        await settle()
        if let groupFrame = LayoutChecks.frames["sidebar-folder-\(placementFolder.id)"], let pinFrame = LayoutChecks.frames["sidebar-tab-\(pin.id)"] {
            check(pinFrame.minY >= groupFrame.maxY - 1, "the standalone pin renders below its group")
        } else { check(false, "the anchored pin and group are rendered") }
        check(LayoutChecks.frames["folder-icon-symbol-\(placementFolder.id)"] != nil, "a default folder with several tabs renders a folder symbol")
        let restored = BrowserState(store: SessionStore(directory: SessionStore.testDirectory.appending(path: "PinPresentation")))
        defer { restored.saveTask?.cancel() }
        restored.apply(state.snapshot())
        check(restored.tab(pin.id)?.pinAsRow == true && restored.tab(peer.id)?.pinAsRow == false && restored.tab(pin.id)?.pinAfterFolderID == placementFolder.id,
              "row and grid placement both survive a session round trip")
        state.togglePin(pin.id)
        check(!pin.pinned, "the same pin action unpins the row")
        state.moveTabToListEnd(peer.id); await settle()
        let listBefore = LayoutChecks.frames["sidebar-tab-list"], gridBefore = LayoutChecks.frames["sidebar-pin-grid"]
        browser.chrome.beginTabDrag(pin.id); await settle()
        check(LayoutChecks.frames["sidebar-tab-list"] == listBefore && LayoutChecks.frames["sidebar-pin-grid"] == gridBefore,
              "starting a drag with an empty grid does not shift the list")
        browser.chrome.endTabDrag(); await settle()

        state.chromeLayout.remove(.assistant)
        state.browserPreferences.pageIntelligence = false
        browser.togglePageAssistant()
        check(!browser.chrome.showPageAssistant && !state.visibleChromeItems(state.chromeLayout.sidebarTop).contains(.assistant),
              "disabled page assistance cannot open and has no toolbar slot")
        state.browserPreferences.pageIntelligence = true
        browser.togglePageAssistant(); await settle()
        check(state.chromeLayout.contains(.assistant), "enabling assistance automatically adds its toolbar control")
        check(browser.chrome.showPageAssistant && state.visibleChromeItems(state.chromeLayout.sidebarTop).contains(.assistant),
              "enabling assistance restores its customized placement")
        state.chromeLayout.place(.assistant, in: .sidebarBottom)
        restored.apply(state.snapshot())
        check(restored.chromeLayout.sidebarBottom.contains(.assistant) && !restored.chromeLayout.sidebarTop.contains(.assistant), "assistant toolbar placement survives restore")
        state.chromeLayout.remove(.assistant)
        restored.apply(state.snapshot())
        check(!restored.chromeLayout.contains(.assistant), "an explicitly removed assistant stays removed on restore")
        var legacy = state.snapshot(); legacy.browser?.assistantToolbarInitialized = nil
        legacy.chrome?.remove(.assistant)
        restored.apply(legacy)
        check(restored.chromeLayout.contains(.assistant), "existing enabled profiles receive the assistant once")
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
        TestDriver.snapshot(window, to: "/private/tmp/ikago-assistant-polished.png")
        check(click("assistant-close", nearEdge: true), "page assistance exposes its full close target")
        await settle()
        check(!browser.chrome.showPageAssistant, "clicking beside the close glyph dismisses assistance")

        state.colorMode = .light
        let folder = state.createFolder(named: "Creative projects")
        browser.customizeFolder(folder.id); await settle()
        if let frame = LayoutChecks.frames["group-appearance-editor"] {
            check(abs(frame.width - 352) < 1 && frame.height < 560, "group editor stays compact with no oversized menu")
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
        browser.customizeFolder(folder.id); await settle()
        if let host = root.firstSubview(of: EmojiPickerHost.self), let field = host.subviews.compactMap({ $0 as? NSTextField }).first {
            window.makeFirstResponder(field); field.selectText(nil)
            if let editor = field.currentEditor() as? NSTextView { editor.insertText("🪴", replacementRange: NSRange(location: 0, length: 0)) }
            await settle()
            _ = click("group-editor-done"); await settle()
            check(state.folders.first { $0.id == folder.id }?.icon == "🪴", "native text insertion delivers a chosen emoji to the draft")
        } else { check(false, "emoji picker has a native input client") }
        check(EmojiPickerButton.emoji(in: "👨‍👩‍👧‍👦") == "👨‍👩‍👧‍👦" && EmojiPickerButton.emoji(in: "🇸🇪") == "🇸🇪" && EmojiPickerButton.emoji(in: "plain") == nil,
              "emoji selection preserves complete joined and flag characters")
        browser.renameFolder(folder.id); await settle()
        TestDriver.snapshot(window, to: "/private/tmp/ikago-rename-polished.png")
        browser.chrome.textPrompt?.finish(nil)
        browser.newSpace(); await settle()
        TestDriver.snapshot(window, to: "/private/tmp/ikago-space-polished.png")
        browser.chrome.showNewSpace = false
        print("IKTEST pinassistantchecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }
}
#endif
