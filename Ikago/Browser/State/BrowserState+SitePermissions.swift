import Foundation

/// A site's camera and microphone choice (the site popover): ask each time, always allow, or always block.
enum SitePermission: String, Codable, CaseIterable, Identifiable {
    case ask, allow, block
    var id: String { rawValue }
    var title: String {
        switch self {
        case .ask: "Ask"
        case .allow: "Allow"
        case .block: "Block"
        }
    }
}

/// Per site (host): unset kinds ask.
struct SitePermissions: Codable, Equatable {
    var camera: SitePermission? = nil
    var microphone: SitePermission? = nil
}

extension BrowserState {
    func sitePermission(_ kind: PermissionRequest.Kinds, host: String) -> SitePermission {
        let saved = browserPreferences.sitePermissions?[host.lowercased()]
        return (kind == .camera ? saved?.camera : saved?.microphone) ?? .ask
    }

    func setSitePermission(_ value: SitePermission, _ kind: PermissionRequest.Kinds, host: String) {
        let host = host.lowercased()
        var all = browserPreferences.sitePermissions ?? [:]
        var entry = all[host] ?? SitePermissions()
        if kind == .camera { entry.camera = value == .ask ? nil : value } else { entry.microphone = value == .ask ? nil : value }
        all[host] = entry == SitePermissions() ? nil : entry
        browserPreferences.sitePermissions = all.isEmpty ? nil : all
    }

    /// What the site's saved choices decide for a request: blocked if any asked-for kind is blocked, allowed if every
    /// one is allowed, otherwise nil (ask). Private windows always ask.
    func rememberedDecision(origin: String, kinds: PermissionRequest.Kinds) -> PermissionRequest.Decision? {
        guard !isPrivate, let host = URL(string: origin)?.host else { return nil }
        let asked = [PermissionRequest.Kinds.camera, .microphone].filter { kinds.contains($0) }
        let choices = asked.map { sitePermission($0, host: host) }
        if choices.contains(.block) { return .deny }
        if !choices.isEmpty, choices.allSatisfy({ $0 == .allow }) { return .allow }
        return nil
    }

    /// Settings ▸ Memory's "always keep these sites awake", for one host.
    func keepsAwake(_ host: String) -> Bool { browserPreferences.protects("https://\(host)") }

    func setKeepsAwake(_ on: Bool, host: String) {
        var entries = browserPreferences.hibernationExceptions.split(whereSeparator: { $0 == "," || $0.isWhitespace }).map(String.init)
        entries.removeAll { $0.lowercased() == host.lowercased() }
        if on { entries.append(host) }
        browserPreferences.hibernationExceptions = entries.joined(separator: ", ")
    }
}
