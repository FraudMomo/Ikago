import AppKit

/// Applies `ExtensionAccess` to Chromium through its own extension service: an extension on every website is set to
/// "on all sites"; one that asks is set to "on specific sites" with exactly the websites the person allowed. Chromium
/// keeps that per Space, so it is lined up again whenever a Space's extensions are read (`perform`).
extension ChromiumExtensions {
    /// The key choices are stored under: the Web Store ID when Ikago installed it from the store (shared with WebKit).
    static func accessKey(_ item: Item) -> String { storeID(of: item) ?? item.id }

    func observeAccess() {
        guard !accessObserved else { return }
        accessObserved = true
        ExtensionAccess.shared.onChange.append { [weak self] key in
            guard let self, let profile = self.profile, self.items.contains(where: { Self.accessKey($0) == key }) else { return }
            Task { await self.refresh(profile: profile) }
        }
    }

    /// Changes Chromium where it differs from the choices; returns whether anything changed.
    func reconcileAccess(_ tool: HiddenChromiumPage) async throws -> Bool {
        observeAccess()
        var changed = false
        for item in items where item.hostAccess != nil {
            let key = Self.accessKey(item)
            let entry = ExtensionAccess.shared.entry(key)
            if entry.everySite {
                guard item.hostAccess != "ON_ALL_SITES" else { continue }
                try await tool.run("chrome.developerPrivate.updateExtensionConfiguration({extensionId: \(Self.json(item.id)), hostAccess: 'ON_ALL_SITES'})")
                changed = true
                continue
            }
            let wanted = Set(ExtensionAccess.shared.allowedSites(key).keys.map(ExtensionAccess.pattern(for:)))
            let granted = Set(item.grantedHosts)
            if item.hostAccess != "ON_SPECIFIC_SITES" {
                try await tool.run("chrome.developerPrivate.updateExtensionConfiguration({extensionId: \(Self.json(item.id)), hostAccess: 'ON_SPECIFIC_SITES'})")
                changed = true
            }
            for host in granted.subtracting(wanted) {
                _ = try? await tool.run("chrome.developerPrivate.removeHostPermission(\(Self.json(item.id)), \(Self.json(host)))")
                changed = true
            }
            for host in wanted.subtracting(granted) {
                _ = try? await tool.run("chrome.developerPrivate.addHostPermission(\(Self.json(item.id)), \(Self.json(host)))")
                changed = true
            }
        }
        return changed
    }

    /// The enabled extensions as the access UI shows them.
    var accessDescriptors: [ExtensionDescriptor] {
        items.filter { $0.enabled && $0.hostAccess != nil }.map { item in
            ExtensionDescriptor(key: Self.accessKey(item), name: item.name, engine: .chromium, icon: item.icon,
                                patterns: item.patterns, abilities: item.abilities)
        }
    }

    static func json(_ value: String) -> String {
        String(data: (try? JSONEncoder().encode(value)) ?? Data(), encoding: .utf8) ?? "\"\""
    }
}
