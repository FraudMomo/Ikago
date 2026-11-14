import AppKit
import CryptoKit

extension FaviconCache {
    /// Synchronous reads avoid a placeholder frame when SwiftUI recreates a tab tile.
    func cachedImage(for url: URL, dark: Bool? = nil) -> NSImage? {
        readCached(key: url.absoluteString, dark: dark)
    }

    /// The page's icon for this mode first (a site may offer a different one in dark mode), then the icon it last
    /// reported, then the site's, then entries saved before modes existed.
    func cachedImage(pageURL: String, iconURL: URL?, dark: Bool? = nil) -> NSImage? {
        let dark = dark ?? self.dark
        let hasOwn = Self.hasOwnIcon(pageURL)
        if hasOwn, let image = readCached(key: Self.modeKey("page:" + pageURL, dark: dark), dark: dark) { return image }
        if let iconURL, let image = cachedImage(for: iconURL, dark: dark) { return image }
        guard hasOwn else { return nil }
        let site = Self.siteKey(pageURL)
        return readCached(key: Self.modeKey("site:" + site, dark: dark), dark: dark)
            ?? readCached(key: "page:" + pageURL, dark: dark) ?? readCached(key: "site:" + site, dark: dark)
    }

    func image(pageURL: String, iconURL: URL, persist: Bool = true, dark: Bool? = nil) async -> NSImage? {
        let dark = dark ?? self.dark
        let pageKey = Self.modeKey("page:" + pageURL, dark: dark), icon = iconURL.absoluteString
        // Already remembered for this page with this icon: nothing to fetch, encode or write.
        if persist, storedIcons[pageKey] == icon, let image = memoryImage(pageURL: pageURL, iconURL: iconURL, dark: dark) { return image }
        let previous = cachedImage(pageURL: pageURL, iconURL: iconURL, dark: dark)
        guard let image = await image(for: iconURL, persist: persist, dark: dark) else { return previous }
        // Keep a last-known-good page/site image even when the reported icon URL changes.
        if persist, Self.hasOwnIcon(pageURL), storedIcons[pageKey] != icon,
           let data = originals.object(forKey: icon as NSString).map({ $0 as Data }) {
            // Only the icon's own (already reduced) bytes are stored. Never `tiffRepresentation`: that writes the
            // decoded bitmap uncompressed, which made 58 MB files for one large icon.
            let siteKey = Self.modeKey("site:" + Self.siteKey(pageURL), dark: dark)
            storeCached(image, data: data, key: pageKey, dark: dark)
            if storedIcons[siteKey] != icon { storeCached(image, data: data, key: siteKey, dark: dark) }
            if storedIcons.count >= 4096 { storedIcons.removeAll() }
            storedIcons[pageKey] = icon
            storedIcons[siteKey] = icon
        }
        return image
    }

    /// Only real sites and extension pages remember an icon by address. about:blank and other hostless
    /// pages would otherwise share one "site" and show whatever icon one of them last had.
    static func hasOwnIcon(_ page: String) -> Bool {
        guard let parts = URLComponents(string: page), let host = parts.host, !host.isEmpty else { return false }
        return ["http", "https", "chrome-extension", "webkit-extension"].contains(parts.scheme?.lowercased() ?? "")
    }

    static func siteKey(_ page: String) -> String {
        guard var parts = URLComponents(string: page) else { return page }
        parts.path = ""; parts.query = nil; parts.fragment = nil
        return parts.string ?? page
    }
}
