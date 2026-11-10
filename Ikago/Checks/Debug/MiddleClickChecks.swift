#if DEBUG
import AppKit
import WebKit

@MainActor
enum MiddleClickChecks {
    static func run(_ browser: BrowserWindowController, base: String) async {
        guard WebProfiles.isTestMode, URL(string: base)?.host == "127.0.0.1" else { return }
        var failures = 0
        func check(_ value: Bool, _ title: String) {
            print("IKTEST middleclick \(value ? "PASS" : "FAIL") \(title)")
            if !value { failures += 1 }
        }
        let state = browser.state
        let originalTabs = Set(state.tabs.map(\.id)), originalActive = state.activeTabID
        let originalLayout = state.tabLayout, originalRounded = state.barRounded
        let originalNew = state.newTabPosition, originalLinks = state.linkTabPosition
        defer {
            for tab in state.tabs where !originalTabs.contains(tab.id) { state.closeTab(tab.id, removingPin: true) }
            state.tabLayout = originalLayout; state.barRounded = originalRounded
            state.newTabPosition = originalNew; state.linkTabPosition = originalLinks
            if let originalActive { state.select(originalActive) }
        }
        browser.palette.onDismiss(); state.tabLayout = .horizontal; state.barRounded = false
        NSApp.activate(); browser.window?.makeKeyAndOrderFront(nil)
        browser.open(base + "/links.html", inNewTab: true)
        for _ in 0..<250 {
            if state.activeTab?.title == "Link fixture" && state.activeTab?.isLoading == false { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        guard let opener = state.activeTab, let page = browser.activeController?.page else { check(false, "fixture loaded"); return }
        for layout in [TabLayout.vertical, .horizontal] {
            state.tabLayout = layout
            try? await Task.sleep(for: .milliseconds(300))
            for policy in LinkTabPosition.allCases {
                state.linkTabPosition = policy; state.newTabPosition = .top
                let before = Set(state.tabs.map(\.id))
                do { try await click("normal", page: page, window: browser.window, middle: true) }
                catch { check(false, error.localizedDescription) }
                try? await Task.sleep(for: .milliseconds(400))
                let added = state.tabs.filter { !before.contains($0.id) }
                check(added.count == 1 && added.first?.url == base + "/middle-target", "native middle-click opens exactly one link tab for \(policy.rawValue)")
                check(state.activeTabID == opener.id && opener.url == base + "/links.html", "middle-click stays in the source tab")
                if let child = added.first {
                    let ids = state.looseTabs.map(\.id), target = ids.firstIndex(of: child.id)!, current = ids.firstIndex(of: opener.id)!
                    // Top layouts always place links after their opener; only the Sidebar honors the setting.
                    let effective = state.effectiveLinkTabPosition
                    check(effective == .beforeCurrent ? target + 1 == current : effective == .afterCurrent ? target == current + 1 : target == 0,
                          "middle-click follows link placement setting")
                }
                for tab in added { state.closeTab(tab.id, removingPin: true) }
            }
        }
        for (element, middle) in [("blank", true), ("normal", false)] {
            let before = Set(state.tabs.map(\.id))
            do { try await click(element, page: page, window: browser.window, middle: middle, flags: middle ? [] : .command) }
            catch { check(false, error.localizedDescription) }
            try? await Task.sleep(for: .milliseconds(400))
            let added = state.tabs.filter { !before.contains($0.id) }
            check(added.count == 1 && state.activeTabID == opener.id && opener.url == base + "/links.html",
                  "\(middle ? "Middle-click target-blank" : "Cmd-click") opens one background tab")
            for tab in added { state.closeTab(tab.id, removingPin: true) }
        }
        let before = Set(state.tabs.map(\.id))
        do { try await click("blank", page: page, window: browser.window, middle: true, flags: .shift) }
        catch { check(false, error.localizedDescription) }
        try? await Task.sleep(for: .milliseconds(400))
        let added = state.tabs.filter { !before.contains($0.id) }
        check(added.count == 1 && state.activeTabID == added.first?.id, "Shift-middle-click opens target-blank link in foreground")
        for tab in added { state.closeTab(tab.id, removingPin: true) }
        state.select(opener.id)
        let beforePopup = Set(state.tabs.map(\.id))
        do { try await click("popup", page: page, window: browser.window, middle: false) }
        catch { check(false, error.localizedDescription) }
        try? await Task.sleep(for: .milliseconds(600))
        let popup = state.tabs.first { !beforePopup.contains($0.id) }
        let controller = popup.flatMap { browser.content.controller(for: $0.id) }
        let hasOpener = try? await controller?.page?.callAsync("return !!window.opener")
        check(popup != nil && hasOpener as? Bool == true, "user-gesture popup preserves WebKit's configuration and window.opener")
        print("IKTEST middleclickchecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }

    private static func click(_ id: String, page: WebTab, window: NSWindow?, middle: Bool, flags: NSEvent.ModifierFlags = []) async throws {
        guard let window, let rect = try await page.callAsync("const r=document.getElementById('\(id)').getBoundingClientRect(); return {x:r.x+r.width/2,y:r.y+r.height/2}") as? [String: Double], let x = rect["x"], let y = rect["y"] else { throw CocoaError(.coderInvalidValue) }
        let view = page.webView
        let location = view.convert(NSPoint(x: x, y: view.isFlipped ? y : view.bounds.height - y), to: nil)
        for type in (middle ? [NSEvent.EventType.otherMouseDown, .otherMouseUp] : [.leftMouseDown, .leftMouseUp]) {
            guard let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                               windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1) else { continue }
            var delivered = event
            if middle {
                // NSEvent.mouseEvent makes button zero for otherMouse events. Fresh CG events
                // carry button two. Deliver directly to this app's web view, using window-local
                // coordinates after the CG-to-AppKit Y flip; no global mouse input is posted.
                let point = NSPoint(x: location.x, y: (NSScreen.screens.first?.frame.height ?? 0) - location.y)
                let cg = CGEvent(mouseEventSource: nil, mouseType: type == .otherMouseDown ? .otherMouseDown : .otherMouseUp,
                                 mouseCursorPosition: point, mouseButton: .center)!
                cg.flags = CGEventFlags(rawValue: UInt64(flags.rawValue))
                delivered = NSEvent(cgEvent: cg)!
            }
            switch type {
            case .otherMouseDown: view.otherMouseDown(with: delivered)
            case .otherMouseUp: view.otherMouseUp(with: delivered)
            case .leftMouseDown: view.mouseDown(with: delivered)
            default: view.mouseUp(with: delivered)
            }
            try? await Task.sleep(for: .milliseconds(30))
        }
    }
}
#endif
