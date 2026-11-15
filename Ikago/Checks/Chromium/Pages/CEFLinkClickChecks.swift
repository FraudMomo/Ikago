import AppKit
import IKCEFBridge

/// ⌘-click, ⇧⌘-click and middle-click on a link open it in a new tab (background, foreground, background) and leave
/// the page where it was. Chromium reports these through OnOpenURLFromTab, not as popups.
@MainActor
enum CEFLinkClickChecks {
    static func run(browser: IKCEFPage) async throws {
        print("CEF_SMOKE_STAGE link-clicks")
        var opened: [(url: String, background: Bool)] = []
        let previous = browser.newTabHandler
        browser.newTabHandler = { url, background in opened.append((url.absoluteString, background)) }
        defer { browser.newTabHandler = previous }
        let before = try await value(browser, "location.href") as? String
        _ = try await value(browser, """
            (() => { const a = document.createElement('a'); a.id = 'ikago-link'; a.href = '/?new-tab-link'; a.textContent = 'link';
                     a.style.cssText = 'position:fixed;left:20px;top:20px;width:120px;height:30px;display:block;z-index:99999';
                     document.body.appendChild(a); return true })()
            """)
        // Chrome DevTools modifier bits: 4 = ⌘, 8 = ⇧.
        for (button, modifiers, background) in [("left", 4, true), ("left", 12, false), ("middle", 0, true)] {
            let count = opened.count
            for type in ["mousePressed", "mouseReleased"] {
                _ = try await CEFSmoke.method(browser, "Input.dispatchMouseEvent",
                                              ["type": type, "x": 60, "y": 35, "button": button, "clickCount": 1, "modifiers": modifiers])
            }
            let deadline = Date().addingTimeInterval(5)
            while opened.count == count, Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
            guard let last = opened.last, opened.count == count + 1, last.url.contains("new-tab-link"), last.background == background
            else { throw CEFError.script("A \(button) click with modifiers \(modifiers) didn't open the link in a new tab.") }
        }
        try await Task.sleep(for: .milliseconds(300))
        guard try await value(browser, "location.href") as? String == before
        else { throw CEFError.script("A new-tab click navigated the page itself.") }
        _ = try await value(browser, "document.getElementById('ikago-link').remove(); true")
        print("CEF_LINK_CLICKS_OK command-shift-middle")
    }

    private static func value(_ page: IKCEFPage, _ expression: String) async throws -> Any? {
        let result = try await CEFSmoke.method(page, "Runtime.evaluate", ["expression": expression, "returnByValue": true])
        return (result["result"] as? [String: Any])?["value"]
    }
}
