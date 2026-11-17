import Foundation

/// How eagerly inactive tabs give back their memory, following what Chrome's Memory Saver and Edge's sleeping tabs do:
/// background tabs left unused for a while are put to sleep (kept in the sidebar, reloaded when selected), and macOS
/// memory-pressure events reclaim more right away. Responsive keeps Safari's behaviour: pressure only.
enum ResourcePolicy: String, CaseIterable, Identifiable, Codable {
    case conservative, balanced, responsive
    var id: String { rawValue }
    var title: String {
        switch self {
        case .conservative: "Conservative"
        case .balanced: "Balanced"
        case .responsive: "Responsive"
        }
    }
    var summary: String {
        switch self {
        case .conservative: "Unused tabs sleep after 30 minutes; memory warnings reclaim more"
        case .balanced: "Unused tabs sleep after 2 hours; memory warnings reclaim more"
        case .responsive: "Tabs stay awake; only critical memory pressure reclaims"
        }
    }
    /// How long a background tab may go unused before it sleeps; nil: never on a timer.
    var idleSleep: Duration? {
        switch self {
        case .conservative: .seconds(30 * 60)
        case .balanced: .seconds(2 * 60 * 60)
        case .responsive: nil
        }
    }
    /// macOS's memory warning (not only critical pressure) reclaims inactive pages.
    var reclaimsOnWarning: Bool { self != .responsive }
}

enum BrowserMemoryPressure { case normal, warning, critical }

extension BrowserPreferences {
    /// Existing profiles retain their opt-in intent; new profiles explicitly choose Conservative.
    var resourcePolicy: ResourcePolicy {
        get { resourcePolicyName.flatMap(ResourcePolicy.init(rawValue:)) ?? (hibernationEnabled ? .conservative : .responsive) }
        set { resourcePolicyName = newValue.rawValue }
    }
}
