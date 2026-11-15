import Foundation
import IKCEFBridge

@MainActor
enum CEFSecurityPreferenceChecks {
    static func run(profile: String) throws {
        let reading = CommandLine.arguments.contains("--cef-smoke-read")
        let initial = IKCEFSecurity.snapshot(forProfile: profile)
        guard initial["cookieControlsMode"] as? Int == (reading ? 2 : 1),
              initial["safeBrowsingEnabled"] as? Bool == !reading else {
            throw CEFError.script("Native per-Space security preferences did not survive restart.")
        }
        let revision = CEFNativePreferences.shared.revision
        try IKCEFSecurity.setPreference("profile.cookie_controls_mode", value: 0, profile: profile)
        try IKCEFSecurity.setPreference("safebrowsing.enabled", value: false, profile: profile)
        try IKCEFSecurity.setPreference("profile.cookie_controls_mode", value: 2, profile: profile)
        guard CEFNativePreferences.shared.revision > revision else { throw CEFError.script("Native security observers did not notify SwiftUI.") }
        IKCEFSecurity.configure(["trackers": true, "cookies": true, "safeBrowsing": true, "domains": BrowserSecurity.trackerDomains])
        let changed = IKCEFSecurity.snapshot(forProfile: profile)
        guard changed["cookieControlsMode"] as? Int == 2, changed["safeBrowsingEnabled"] as? Bool == false else {
            throw CEFError.script("An app protection update overwrote native user settings.")
        }
        print("CEF_SECURITY_PREFERENCES_OK observer native-user-values-preserved restart cookie-mode-2")
    }
}
