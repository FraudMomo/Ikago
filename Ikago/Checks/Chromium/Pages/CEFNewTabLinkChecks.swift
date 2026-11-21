import AppKit
import QuartzCore

/// A link ⌘-clicked (background) or ⇧⌘-clicked (foreground) in a Chromium page opens a tab that actually loads, and
/// shows its page with a real viewport once selected. `CEFLinkClickChecks` covers only the click reaching Ikago.
@MainActor
enum CEFNewTabLinkChecks {
    static func run(_ shell: BrowserWindowController, from id: String, url: String) async throws {
        let state = shell.state
        state.select(id)
        try await wait { shell.content.controller(for: id)?.page != nil }
        guard let opener = shell.content.controller(for: id), let page = opener.page else { throw CEFError.script("No opener page.") }
        let loads = state.browserPreferences.loadBackgroundTabs
        defer { state.browserPreferences.loadBackgroundTabs = loads }
        for (background, eager) in [(true, true), (true, false), (false, true)] {
            state.browserPreferences.loadBackgroundTabs = eager ? nil : false
            let target = url + (url.contains("?") ? "&" : "?") + (background ? (eager ? "background-link" : "lazy-link") : "foreground-link")
            let before = Set(state.tabs.map(\.id))
            opener.webTab(page, openInNewTab: target, background: background)
            try await wait { state.tabs.contains { !before.contains($0.id) } }
            guard let tab = state.tabs.first(where: { !before.contains($0.id) }) else { throw CEFError.script("No new tab.") }
            // As in use: the background tab loads hidden for a while before it's chosen.
            if background {
                try await Task.sleep(for: .seconds(2))
                let hidden = shell.content.controller(for: tab.id)?.page
                print("CEF_NEW_TAB_LINK hidden page=\(hidden != nil) loading=\(hidden?.isLoading ?? true) url=\(hidden?.currentURL ?? "-") size=\(hidden.map { NSStringFromSize($0.contentView.bounds.size) } ?? "-")")
                state.select(tab.id)
            }
            try await wait {
                guard let page = shell.content.controller(for: tab.id)?.page else { return false }
                return !page.isLoading && page.currentURL == target
            }
            var report = ""
            try await CEFWait.until("A \(background ? "background" : "foreground") link tab didn't load or show its page.") {
                guard let page = shell.content.controller(for: tab.id)?.page as? CEFWebTab,
                      let shown = try await page.callAsync("return await new Promise(r => requestAnimationFrame(() => r(JSON.stringify({ready: document.readyState, visible: document.visibilityState, width: innerWidth, height: innerHeight}))))") as? String else { return false }
                report = shown
                return shown.contains("\"ready\":\"complete\"") && shown.contains("\"visible\":\"visible\"") && !shown.contains("\"width\":0")
                    && page.contentView.bounds.width > 0
            }
            print("CEF_NEW_TAB_LINK \(background ? (eager ? "background" : "lazy") : "foreground") \(report)")
            state.closeTab(tab.id)
            state.select(id)
            try await Task.sleep(for: .milliseconds(200))
        }
    }

    /// Real clicks (DevTools input) on a `target=_blank` link: Chromium sends these through OnBeforePopup, and Ikago
    /// adopts the popup's page as a tab (`adoptCEFPopup`), the path that once left link tabs blank.
    static func runBlankTarget(_ shell: BrowserWindowController, from id: String, url: String) async throws {
        let state = shell.state
        state.select(id)
        try await wait { shell.content.controller(for: id)?.page is CEFWebTab }
        guard let page = shell.content.controller(for: id)?.page as? CEFWebTab else { throw CEFError.script("No opener page.") }
        for (modifiers, label) in [(4, "command"), (0, "plain")] {
            let target = url + (url.contains("?") ? "&" : "?") + "blank-\(label)"
            _ = try await page.callAsync("""
                document.getElementById('ikago-blank')?.remove();
                const a = document.createElement('a'); a.id = 'ikago-blank'; a.href = '\(target)'; a.target = '_blank'; a.textContent = 'blank';
                a.style.cssText = 'position:fixed;left:20px;top:80px;width:120px;height:30px;display:block;z-index:99999';
                document.body.appendChild(a); return true
                """)
            let before = Set(state.tabs.map(\.id))
            for type in ["mousePressed", "mouseReleased"] {
                _ = try await page.devTools("Input.dispatchMouseEvent", ["type": type, "x": 60, "y": 95, "button": "left", "clickCount": 1, "modifiers": modifiers])
            }
            try await wait { state.tabs.contains { !before.contains($0.id) } }
            guard let tab = state.tabs.first(where: { !before.contains($0.id) }) else { throw CEFError.script("No blank-target tab.") }
            try await Task.sleep(for: .seconds(1.5))
            state.select(tab.id)
            try await wait {
                guard let page = shell.content.controller(for: tab.id)?.page else { return false }
                return !page.isLoading && page.currentURL == target
            }
            var report = ""
            try await CEFWait.until("A \(label)-clicked target=_blank tab didn't load or show its page.") {
                guard let child = shell.content.controller(for: tab.id)?.page as? CEFWebTab,
                      let shown = try await child.callAsync("return await new Promise(r => requestAnimationFrame(() => r(JSON.stringify({ready: document.readyState, visible: document.visibilityState, width: innerWidth, height: innerHeight}))))") as? String else { return false }
                report = shown
                return shown.contains("\"visible\":\"visible\"") && !shown.contains("\"width\":0")
            }
            print("CEF_NEW_TAB_LINK blank-\(label) \(report)")
            state.closeTab(tab.id)
            state.select(id)
            try await Task.sleep(for: .milliseconds(200))
        }
        _ = try await page.callAsync("document.getElementById('ikago-blank')?.remove(); return true")
    }

    private static func wait(_ condition: () -> Bool) async throws {
        try await CEFWait.until("A link tab timed out loading.") { condition() }
    }
}

/// Peek ▸ Open as Tab on Chromium: the kept page and Chromium's own view inside it fill the pane, as a normal tab's do.
@MainActor
enum CEFPeekKeepChecks {
    /// Open as Tab keeps the same live page (no reload). Where it draws is measured by the Debug `peekshot` action with
    /// `IKAGO_CEF_SOFTWARE_COMPOSITING=1`: hidden check windows report meaningless GPU layer sizes even for normal tabs.
    static func run(_ shell: BrowserWindowController, from id: String, url: String) async throws {
        let state = shell.state
        state.select(id)
        try await Task.sleep(for: .milliseconds(500))
        let target = url + (url.contains("?") ? "&" : "?") + "peek-keep"
        shell.peekLink(target)
        try await CEFWait.until("The Peek of a Chromium link didn't load.") { shell.peekController?.page?.isLoading == false }
        let previewed = shell.peekController?.page
        shell.openPeek()
        try await CEFWait.until("Open as Tab didn't keep the Chromium page.") {
            guard shell.chrome.previewTabID == nil, let kept = shell.activeController, let page = kept.page else { return false }
            return kept.tab.url == target && page.contentView.frame == kept.hostView.bounds
        }
        guard let kept = shell.activeController, kept.tab.url == target, let page = kept.page else {
            throw CEFError.script("Open as Tab didn't keep the Chromium page.")
        }
        guard page === previewed, page.contentView.window != nil, page.contentView.frame == kept.hostView.bounds else {
            throw CEFError.script("Open as Tab didn't move the live page into its tab.")
        }
        state.closeTab(kept.tab.id)
        state.select(id)
        try await Task.sleep(for: .milliseconds(300))
    }
}
