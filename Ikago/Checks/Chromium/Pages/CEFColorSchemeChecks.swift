import AppKit
import IKCEFBridge

/// Chromium pages follow Ikago's light/dark mode (`ChromiumAppearance`), not macOS's. Both directions are checked,
/// so the result never depends on the Mac's own appearance.
@MainActor
enum CEFColorSchemeChecks {
    static func run(_ page: IKCEFPage) async throws {
        defer { ChromiumAppearance.apply(dark: nil) }
        for dark in [true, false, true, false] {
            ChromiumAppearance.apply(dark: dark)
            var reported: Bool?
            // The renderer hears about the change asynchronously.
            try? await CEFWait.until("") {
                let result = try await CEFSmoke.method(page, "Runtime.evaluate", [
                    "expression": "matchMedia('(prefers-color-scheme: dark)').matches", "returnByValue": true])
                reported = (result["result"] as? [String: Any])?["value"] as? Bool
                return reported == dark
            }
            guard reported == dark else {
                throw CEFError.script("A Chromium page reported \(reported.map { $0 ? "dark" : "light" } ?? "nothing") after Ikago chose \(dark ? "dark" : "light").")
            }
        }
        try CEFHiddenServiceChecks.noVisibleChromiumWindows()
        print("CEF_COLOR_SCHEME_OK dark light dark light")
    }
}
