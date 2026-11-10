import AppKit
import CryptoKit

extension FaviconCache {
    /// Synchronous reads avoid a placeholder frame when SwiftUI recreates a tab tile.
    func cachedImage(for url: URL) -> NSImage? {
        readCached(key: url.absoluteString)
    }

    func cachedImage(pageURL: String, iconURL: URL?) -> NSImage? {
        if let iconURL, let image = cachedImage(for: iconURL) { return image }
        guard Self.hasOwnIcon(pageURL) else { return nil }
        return readCached(key: "page:" + pageURL) ?? readCached(key: "site:" + Self.siteKey(pageURL))
    }

    func image(pageURL: String, iconURL: URL, persist: Bool = true) async -> NSImage? {
        let pageKey = "page:" + pageURL, icon = iconURL.absoluteString
        // Already remembered for this page with this icon: nothing to fetch, encode or write.
        if persist, storedIcons[pageKey] == icon, let image = memoryImage(pageURL: pageURL, iconURL: iconURL) { return image }
        let previous = cachedImage(pageURL: pageURL, iconURL: iconURL)
        guard let image = await image(for: iconURL, persist: persist) else { return previous }
        // Keep a last-known-good page/site image even when the reported icon URL changes.
        if persist, Self.hasOwnIcon(pageURL), storedIcons[pageKey] != icon,
           let data = originals.object(forKey: icon as NSString).map({ $0 as Data }) {
            // Only the icon's own (already reduced) bytes are stored. Never `tiffRepresentation`: that writes the
            // decoded bitmap uncompressed, which made 58 MB files for one large icon.
            let siteKey = "site:" + Self.siteKey(pageURL)
            storeCached(image, data: data, key: pageKey)
            if storedIcons[siteKey] != icon { storeCached(image, data: data, key: siteKey) }
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
