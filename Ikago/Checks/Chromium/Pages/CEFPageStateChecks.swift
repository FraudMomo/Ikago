import AppKit
import IKCEFBridge

/// Idle pages need no repeated state evaluations; media/theme changes still arrive from isolated contexts.
@MainActor
enum CEFPageStateChecks {
    static func run(_ tab: CEFWebTab) async throws {
        try await CEFWait.until("Page state binding did not install.") { !tab.pageStateContexts.isEmpty }
        guard let pid = tab.performanceProcessID, pid > 0, pid != getpid() else {
            throw CEFError.script("Renderer did not report its process identity for diagnostics.")
        }
        let monitor = PerformanceMonitor.shared
        let subscription = monitor.subscribe()
        defer { monitor.unsubscribe(subscription) }
        try await CEFWait.until("Renderer footprint was not attributed to Chromium.") {
            monitor.sample.rows.contains { $0.id == pid && $0.owner == .chromium }
        }
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
        try await CEFWait.until("Theme changes did not arrive without polling.") {
            guard let color = tab.lastPolledThemeColor?.usingColorSpace(.sRGB) else { return false }
            return abs(color.redComponent - 18.0/255) < 0.01
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
