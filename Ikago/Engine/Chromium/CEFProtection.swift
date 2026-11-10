import Foundation
import IKCEFBridge

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
            "domains": BrowserSecurity.trackerDomains, "forceHTTPS": preferences.forceHTTPS ?? false,
            "allowLocal": preferences.httpsAllowLocal ?? true, "exceptions": exceptions])
    }
}
