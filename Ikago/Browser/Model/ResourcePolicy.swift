import Foundation

/// A response to system memory pressure, rather than a per-tab timer or an application memory quota.
enum ResourcePolicy: String, CaseIterable, Identifiable, Codable {
    case conservative, responsive
    var id: String { rawValue }
    var title: String { self == .conservative ? "Conservative" : "Responsive" }
    var summary: String {
        self == .conservative ? "Reclaim on memory warnings" : "Reclaim only under critical pressure"
    }
}

enum BrowserMemoryPressure { case normal, warning, critical }

extension BrowserPreferences {
    /// Existing profiles retain their opt-in intent; new profiles explicitly choose Conservative.
    var resourcePolicy: ResourcePolicy {
        get { resourcePolicyName.flatMap(ResourcePolicy.init(rawValue:)) ?? (hibernationEnabled ? .conservative : .responsive) }
        set { resourcePolicyName = newValue.rawValue }
    }
}
