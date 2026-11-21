import Foundation
import IKCEFBridge

/// How the Chromium checks wait: for the thing a check needs, never for a guessed time, with one generous limit. A slow
/// machine (GitHub's runners, a new Chromium) then makes a check slower, not failed. A fixed pause belongs only where a
/// check proves something did *not* happen.
@MainActor
enum CEFWait {
    static let limit: Duration = .seconds(30)

    /// Checks `condition` every 50 ms until it holds; an error inside it counts as "not yet" (a page mid-navigation).
    static func until(_ what: String, limit: Duration = limit, _ condition: @MainActor () async throws -> Bool) async throws {
        let deadline = ContinuousClock.now + limit
        while true {
            if (try? await condition()) == true { return }
            guard ContinuousClock.now < deadline else { throw CEFError.script(what) }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    /// Runs `navigate` (a load or reload) and waits for its new document to finish loading. A mark left in the old
    /// document tells the two apart, so a navigation that starts late can't pass for one that's done.
    static func newDocument(_ page: IKCEFPage, _ what: String = "The page didn't load a new document.", _ navigate: () -> Void) async throws {
        _ = try await CEFSmoke.method(page, "Runtime.evaluate", ["expression": "window.__ikagoCheckOldDocument = true"])
        navigate()
        try await until(what) {
            guard !page.loading else { return false }
            let result = try await CEFSmoke.method(page, "Runtime.evaluate", ["expression":
                "window.__ikagoCheckOldDocument !== true && document.readyState === 'complete'", "returnByValue": true])
            return (result["result"] as? [String: Any])?["value"] as? Bool == true
        }
    }
}
