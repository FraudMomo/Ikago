import AppKit
import IKCEFBridge

/// Idle pages need no repeated state evaluations; media/theme changes still arrive from isolated contexts.
@MainActor
enum CEFPageStateChecks {
    static func run(_ tab: CEFWebTab) async throws {
        for _ in 0..<100 {
            if !tab.pageStateContexts.isEmpty { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        guard !tab.pageStateContexts.isEmpty else { throw CEFError.script("Page state binding did not install.") }
        _ = try await tab.evaluate("""
            (() => {
              const original = window.__ikagoMedia.state;
              window.__resourceStateReads = 0;
              window.__ikagoMedia.state = () => { window.__resourceStateReads++; return original(); };
              return true;
            })()
            """)
        try await Task.sleep(for: .seconds(3))
        guard try await tab.evaluate("window.__resourceStateReads") as? Int == 0 else {
            throw CEFError.script("An idle page was polled for media state.")
        }
        _ = try await tab.evaluate("""
            (() => { const meta=document.createElement('meta');meta.name='theme-color';meta.content='#123456';
              document.head.append(meta);return true; })()
            """)
        try await Task.sleep(for: .milliseconds(250))
        guard let color = tab.lastPolledThemeColor?.usingColorSpace(.sRGB), abs(color.redComponent - 18.0/255) < 0.01 else {
            throw CEFError.script("Theme changes did not arrive without polling.")
        }
        // Existing native-output fixture also emits real play/pause events to the adapter.
        try await CEFAudioChecks.run(tab.page)
        let publicWorld = try await CEFSmoke.method(tab.page, "Runtime.evaluate", [
            "expression": "typeof window.__ikagoStateChanged", "returnByValue": true])
        guard (publicWorld["result"] as? [String: Any])?["value"] as? String == "undefined" else {
            throw CEFError.script("The page could see the browser's state binding.")
        }
        tab.stopCapture(camera: true, microphone: true)
        guard try await tab.evaluate("window.fixtureLayoutIdentity") as? String == "retained" else {
            throw CEFError.script("Stopping inactive capture reloaded a page.")
        }
        print("CEF_PAGE_STATE_OK idle-reads=0 theme-events native-audio isolated-binding no-idle-capture-reload")
    }
}
