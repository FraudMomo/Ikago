import AppKit

/// Switching away from a Chromium tab and back must leave its page alone: no resize while hidden (ChatGPT's message
/// list lost its scroll position and the page blinked) and the same scroll position.
@MainActor
enum CEFTabSwitchChecks {
    static func run(_ shell: BrowserWindowController, page: CEFWebTab, tab id: String, other: String) async throws {
        let state = shell.state
        state.select(id)
        try await Task.sleep(for: .milliseconds(400))
        _ = try await page.callAsync("""
            document.body.style.height = '20000px'; window.scrollTo(0, 5000); window.__ikSizes = [];
            addEventListener('resize', () => window.__ikSizes.push(innerWidth + 'x' + innerHeight)); return true
            """)
        for _ in 0..<2 {
            state.select(other)
            try await Task.sleep(for: .milliseconds(400))
            state.select(id)
            try await Task.sleep(for: .milliseconds(400))
        }
        // Any resize fails but one to the page's own size (Chromium reflows nothing for that).
        let report = try await page.callAsync("""
            const own = innerWidth + 'x' + innerHeight;
            return JSON.stringify({resized: window.__ikSizes.some(size => size !== own), sizes: window.__ikSizes, scroll: scrollY})
            """) as? String ?? ""
        print("CEF_TAB_SWITCH \(report)")
        guard report.contains("\"resized\":false"), report.contains("\"scroll\":5000") else {
            throw CEFError.script("Switching tabs resized or scrolled a Chromium page: \(report)")
        }
        _ = try await page.callAsync("document.body.style.height = ''; window.scrollTo(0, 0); return true")
    }
}
