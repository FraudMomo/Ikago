import Foundation

/// Extensions that replace the new tab page (Momentum…), on whichever engine is running. IDs are Web Store
/// IDs where there is one, so the chosen extension stays chosen after switching engines.
@MainActor
enum NewTabProviders {
    struct Provider: Identifiable, Equatable {
        let id: String
        let name: String
        let url: URL
    }

    static var current: [Provider] {
        if BrowserRuntime.engine == .chromium {
            return ChromiumExtensions.shared.items.compactMap { item in
                guard item.enabled, let page = item.newTabPage,
                      let url = URL(string: "chrome-extension://\(item.id)/\(page.hasPrefix("/") ? String(page.dropFirst()) : page)") else { return nil }
                return Provider(id: ChromiumExtensions.storeID(of: item) ?? item.id, name: item.name, url: url)
            }
        }
        return ExtensionManager.shared.loaded.compactMap { context in
            guard let url = context.overrideNewTabPageURL else { return nil }
            return Provider(id: context.uniqueIdentifier, name: context.webExtension.displayName ?? "Extension", url: url)
        }
    }

    /// The chosen extension's page, or the first one available.
    static func page(chosen id: String?) -> URL? {
        let all = current
        return (all.first { $0.id == id } ?? all.first)?.url
    }
}
