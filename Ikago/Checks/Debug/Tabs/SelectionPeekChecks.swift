#if DEBUG
import AppKit

/// Peek's setting (`BrowserState.peeks`), saved site permissions (`rememberedDecision`) and acting on several selected
/// tabs (`TabClick.group`, `moveTabsToNewWindow`).
@MainActor
enum SelectionPeekChecks {
    static func run(_ browser: BrowserWindowController) async {
        let state = browser.state, original = state.browserPreferences
        var failures = 0
        func check(_ value: Bool, _ title: String) {
            print("IKTEST selectionpeek \(value ? "PASS" : "FAIL") \(title)")
            if !value { failures += 1 }
        }
        defer {
            state.browserPreferences = original
            print("IKTEST selectionpeekchecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
        }
        let other = URL(string: "https://other.example/page")!, same = URL(string: "https://www.pinned.example/b")!
        let pinned = TabItem(url: "https://pinned.example/a", pinned: true), plain = TabItem(url: "https://plain.example/")
        check(state.peeks(other, trigger: .shiftClick, in: plain, pageURL: plain.url), "Shift-click peeks by default")
        check(!state.peeks(other, trigger: .link, in: pinned, pageURL: pinned.url), "plain links don't peek unless Automatic")
        state.browserPreferences.linkPeek = .off
        check(!state.peeks(other, trigger: .shiftClick, in: plain, pageURL: plain.url), "Peek off: Shift-click doesn't peek")
        state.browserPreferences.linkPeek = .automatic
        check(state.peeks(other, trigger: .link, in: pinned, pageURL: pinned.url), "Automatic: another site from a pinned tab peeks")
        check(!state.peeks(same, trigger: .link, in: pinned, pageURL: pinned.url), "Automatic: the pinned tab's own site stays in the tab")
        check(state.peeks(other, trigger: .link, in: plain, pageURL: "https://www.google.com/search?q=x"), "Automatic: search results peek")
        check(!state.peeks(other, trigger: .newTabLink, in: plain, pageURL: plain.url), "new-tab links peek only when chosen")
        state.browserPreferences.peekNewTabLinks = true
        check(state.peeks(other, trigger: .newTabLink, in: plain, pageURL: plain.url), "new-tab links peek when chosen")

        state.setSitePermission(.allow, .camera, host: "meet.example")
        check(state.rememberedDecision(origin: "https://meet.example", kinds: .camera) == .allow, "an allowed camera is granted without asking")
        check(state.rememberedDecision(origin: "https://meet.example", kinds: [.camera, .microphone]) == nil, "an unset microphone still asks")
        state.setSitePermission(.block, .microphone, host: "meet.example")
        check(state.rememberedDecision(origin: "https://meet.example", kinds: [.camera, .microphone]) == .deny, "a blocked kind denies the request")
        state.setSitePermission(.ask, .camera, host: "meet.example"); state.setSitePermission(.ask, .microphone, host: "meet.example")
        check(state.browserPreferences.sitePermissions == nil, "choosing Ask again forgets the site")

        guard let a = state.newTab(url: "https://one.example/"), let b = state.newTab(url: "https://two.example/"),
              let c = state.newTab(url: "https://three.example/") else { return check(false, "opens tabs") }
        browser.chrome.selectedTabIDs = [c.id, a.id]
        check(TabClick.group(including: a.id, state: state, chrome: browser.chrome) == [a.id, c.id]
              || TabClick.group(including: a.id, state: state, chrome: browser.chrome) == [c.id, a.id], "a selected tab's group is the selection")
        check(TabClick.group(including: b.id, state: state, chrome: browser.chrome) == [b.id], "an unselected tab acts alone")
        TabDrag.companions = [c.id, a.id]
        check(TabDrag.travelling(with: b.id) == [b.id, a.id, c.id] && TabDrag.companions.isEmpty,
              "a drop takes the dragged tab and the selected ones with it, in sidebar order")
        if let folder = Optional(state.createFolder(named: "Selection probe")) {
            for id in [a.id, c.id] { state.moveToFolder(id, folderID: folder.id) }
            check(state.tab(a.id)?.folderID == folder.id && state.tab(c.id)?.folderID == folder.id, "the selection lands in the group together")
            for id in [a.id, c.id] { state.moveToFolder(id, folderID: nil) }
            state.deleteFolder(folder.id)
        }
        browser.moveTabsToNewWindow([a.id, c.id])
        try? await Task.sleep(for: .milliseconds(500))
        let window = BrowserWindows.others.last
        check(window?.state.tab(a.id) != nil && window?.state.tab(c.id) != nil && state.tab(b.id) != nil,
              "Move Tabs to New Window takes every selected tab")
        check(browser.chrome.selectedTabIDs.isEmpty, "the selection ends after acting on it")
        window?.window?.close()
        try? await Task.sleep(for: .milliseconds(300))
        browser.closeTab(b.id)

        // Open as Tab: the peeked page grows into place and becomes the tab itself, never a reload in a new tab.
        try? await Task.sleep(for: .milliseconds(500))  // the tab switch above closes any Peek once it lands
        let keptURL = "https://example.com/?peek-keep"  // Peek takes web addresses only
        // From a tab with another after it: the kept tab goes where a link from it would (right after, by default).
        let opener = state.activeTab
        let later = state.newTab(url: "about:blank", select: false)
        if let opener { state.select(opener.id) }
        try? await Task.sleep(for: .milliseconds(400))
        browser.peekLink(keptURL)
        for _ in 0..<60 where browser.peekController?.page?.isLoading != false { try? await Task.sleep(for: .milliseconds(100)) }
        let peeked = browser.peekController?.page
        _ = try? await peeked?.callAsync("window.__ikKept = 1; return true")
        browser.openPeek()
        // Chromium loads the address in a tab behind the grown card first, so wait for the preview to close.
        for _ in 0..<60 where browser.chrome.previewTabID != nil { try? await Task.sleep(for: .milliseconds(100)) }
        try? await Task.sleep(for: .milliseconds(300))
        let kept = browser.activeController
        let marker = try? await kept?.page?.callAsync("return window.__ikKept ?? 0") as? Int
        if peeked?.engine == .webkit {
            check(peeked != nil && kept?.page === peeked && marker == 1, "Open as Tab keeps the previewed page (no reload)")
        }
        check(browser.chrome.previewTabID == nil && !browser.chrome.peekExpanding && kept?.tab.url == keptURL,
              "Open as Tab ends the preview on the new tab")
        let order = state.sidebarOrder.map(\.id)
        if state.effectiveLinkTabPosition == .afterCurrent, let opener, let kept,
           let at = order.firstIndex(of: kept.tab.id), let from = order.firstIndex(of: opener.id) {
            check(at == from + 1, "Open as Tab places the tab right after the one it was opened from")
        }
        if let id = kept?.tab.id { browser.closeTab(id) }
        if let later { browser.closeTab(later.id) }
        try? await Task.sleep(for: .milliseconds(500))  // let the tab switch land before the next check opens anything
    }
}
#endif
