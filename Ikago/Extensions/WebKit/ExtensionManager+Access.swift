import WebKit

/// Applies `ExtensionAccess` to WebKit: an extension on every website gets the sites it requested; one that asks gets
/// only the websites the person allowed (a one-day allowance carries WebKit's own expiry), and is kept off the ones
/// they refused. Its other permissions (storage, tabs…) were approved when it was added.
extension ExtensionManager {
    func observeAccess() {
        ExtensionAccess.shared.onChange.append { [weak self] key in self?.applyAccess(key) }
    }

    func applyAccess(_ key: String) {
        guard let context = contexts[key] else { return }
        Self.applyAccess(context, key: key)
    }

    static func applyAccess(_ context: WKWebExtensionContext, key: String) {
        let ext = context.webExtension
        for permission in ext.requestedPermissions { context.setPermissionStatus(.grantedExplicitly, for: permission) }
        let entry = ExtensionAccess.shared.entry(key)
        // Start clean, so a website the person stopped deciding for (Ask Next Time) loses what it had.
        for pattern in Set(context.grantedPermissionMatchPatterns.keys).union(context.deniedPermissionMatchPatterns.keys) {
            context.setPermissionStatus(.unknown, for: pattern)
        }
        for pattern in ext.allRequestedMatchPatterns {
            context.setPermissionStatus(entry.everySite ? .grantedExplicitly : .unknown, for: pattern)
        }
        for (site, grant) in entry.sites {
            guard let pattern = try? WKWebExtension.MatchPattern(string: ExtensionAccess.pattern(for: site)) else { continue }
            switch grant {
            case .always: context.setPermissionStatus(.grantedExplicitly, for: pattern)
            case .never: context.setPermissionStatus(.deniedExplicitly, for: pattern)
            case .until(let date) where date > .now: context.setPermissionStatus(.grantedExplicitly, for: pattern, expirationDate: date)
            case .until: context.setPermissionStatus(.unknown, for: pattern)
            }
        }
    }

    /// The loaded extensions as the access UI shows them.
    var accessDescriptors: [ExtensionDescriptor] {
        records.filter(\.enabled).compactMap { record in
            guard let context = contexts[record.id] else { return nil }
            let ext = context.webExtension
            return ExtensionDescriptor(key: record.id, name: ext.displayName ?? record.id, engine: .webkit,
                                       icon: ext.icon(for: CGSize(width: 32, height: 32)),
                                       patterns: ext.allRequestedMatchPatterns.map(\.string),
                                       abilities: ExtensionPrompts.describe(permissions: ext.requestedPermissions,
                                                                            patterns: ext.allRequestedMatchPatterns))
        }
    }
}

/// One extension, engine aside, for the site card, the first-visit card and Settings.
struct ExtensionDescriptor: Identifiable, Equatable {
    let key: String
    let name: String
    let engine: BrowserEngine
    let icon: NSImage?
    /// Match patterns for the sites it reads (host permissions and content scripts).
    let patterns: [String]
    /// What it can do, in plain words.
    let abilities: [String]
    var id: String { "\(engine.rawValue):\(key)" }

    @MainActor func wants(_ url: URL) -> Bool { ExtensionAccess.wants(patterns, url) }
}
