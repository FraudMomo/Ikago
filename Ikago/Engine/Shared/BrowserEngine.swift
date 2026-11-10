import Foundation

/// Page backend, independent of TabLayout. Raw values are persisted separately
/// so a layout change can never silently change website storage or services.
enum BrowserEngine: String, CaseIterable, Codable, Identifiable, Sendable {
    case webkit
    case chromium

    var id: String { rawValue }
    var title: String { self == .webkit ? "WebKit" : "Chromium" }
}

extension BrowserPreferences {
    /// WebKit unless the user chose otherwise, so nobody changes engine silently.
    var preferredEngine: BrowserEngine {
        get { browserEngine.flatMap(BrowserEngine.init(rawValue:)) ?? .webkit }
        set { browserEngine = newValue.rawValue }
    }
}

enum CEFVersion {
    static let chromium = "156.0.8078.88"
}
