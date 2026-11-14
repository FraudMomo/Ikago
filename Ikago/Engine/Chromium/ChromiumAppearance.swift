import AppKit
import IKCEFBridge

/// Chromium pages follow Ikago's light/dark mode, not macOS's. On macOS, Chromium themes page content
/// (`prefers-color-scheme`, form controls, scrollbars) from the app's appearance, so Ikago sets `NSApp.appearance`;
/// CEF's `SetChromeColorScheme` covers Chromium's own UI (docked DevTools). Both are public, app-wide settings.
@MainActor
enum ChromiumAppearance {
    /// `dark` nil follows macOS: the app's appearance is cleared, so Ikago's system-mode detection keeps working.
    static func apply(dark: Bool?) {
        let target = dark.map { NSAppearance(named: $0 ? .darkAqua : .aqua) } ?? nil
        if NSApp.appearance?.name != target?.name { NSApp.appearance = target }
        IKCEFContexts.setColorScheme(dark.map { $0 ? 2 : 1 } ?? 0)
    }
}
