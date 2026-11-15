import Foundation
import Observation
import IKCEFBridge
import AppKit

// MARK: - Native preferences
/// Chromium owns and persists these per-Space settings; SwiftUI observes that same source.
@MainActor @Observable
final class CEFNativePreferences {
    static let shared = CEFNativePreferences()
    private(set) var revision = 0
    private init() {
        IKCEFSecurity.setChangeHandler { [weak self] _ in
            MainActor.assumeIsolated { self?.revision &+= 1 }
        }
    }
}

// MARK: - Protection
@MainActor
enum CEFProtection {
    private static var last: SecuritySettings?
    static func apply(_ preferences: BrowserPreferences) {
        _ = CEFNativePreferences.shared
        let settings = SecuritySettings(preferences)
        guard last != settings else { return }
        last = settings
        let exceptions = (preferences.httpsExceptions ?? "").split(whereSeparator: { $0 == "," || $0.isWhitespace }).compactMap { raw -> String? in
            let value = String(raw).lowercased()
            return URLComponents(string: value.contains("://") ? value : "http://" + value)?.host?.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        }
        IKCEFSecurity.configure(["trackers": preferences.blockTrackers ?? true,
            "cookies": preferences.blockThirdPartyCookies ?? true,
            "safeBrowsing": preferences.fraudulentWebsiteWarning ?? true,
            "domains": BrowserSecurity.trackerDomains, "trackerExceptions": preferences.trackerExceptions ?? [], "forceHTTPS": preferences.forceHTTPS ?? false,
            "allowLocal": preferences.httpsAllowLocal ?? true, "exceptions": exceptions])
    }
}

// MARK: - Appearance
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
