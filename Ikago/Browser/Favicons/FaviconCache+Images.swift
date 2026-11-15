import AppKit
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Normalize
/// Icons are drawn at 24 pt at most, so anything larger than `maxPixels` is wasted memory and disk.
/// A site can send a 4096 px PNG as its icon, and before this existed the page/site copies were saved as
/// uncompressed TIFF: 58 MB per page, decoded on the main thread at every launch.
extension FaviconCache {
    nonisolated static let maxPixels = 64
    /// Small, already-compact files keep their original bytes (an ICO keeps all its sizes).
    nonisolated static let keepOriginalBytes = 32 * 1024

    /// The bytes to cache and store for an icon: the original when it is small, otherwise a PNG of at most
    /// `maxPixels` on its longest side, rendered by ImageIO without decoding the full image. SVG is text and
    /// stays as it is. Nil when the data isn't an image.
    nonisolated static func normalized(_ data: Data) -> Data? {
        guard isFaviconFormat(data) else { return nil }
        if isSVG(data) { return data }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0 else { return nil }
        let index = largestImage(in: source)
        let (width, height) = pixelSize(source, index)
        if data.count <= keepOriginalBytes, max(width, height) <= maxPixels * 2 { return data }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
            kCGImageSourceShouldCacheImmediately: false,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, thumbnail, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }

    /// An ICO holds several sizes; the largest gives the sharpest thumbnail.
    nonisolated private static func largestImage(in source: CGImageSource) -> Int {
        let count = CGImageSourceGetCount(source)
        guard count > 1 else { return 0 }
        return (0..<count).max { lhs, rhs in
            let a = pixelSize(source, lhs), b = pixelSize(source, rhs)
            return a.0 * a.1 < b.0 * b.1
        } ?? 0
    }

    nonisolated private static func pixelSize(_ source: CGImageSource, _ index: Int) -> (Int, Int) {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
        return (properties?[kCGImagePropertyPixelWidth] as? Int ?? 0, properties?[kCGImagePropertyPixelHeight] as? Int ?? 0)
    }

    nonisolated private static func isSVG(_ data: Data) -> Bool {
        let text = String(decoding: data.prefix(1024), as: UTF8.self).drop { $0.isWhitespace || $0 == "\u{FEFF}" }.lowercased()
        return text.hasPrefix("<svg") || text.hasPrefix("<?xml") || text.hasPrefix("<!--")
    }

    /// Shrinks icons saved before normalization existed, off the main thread. Files over the threshold are
    /// opened, reduced and sealed again in place; everything else is only a size check.
    nonisolated static func shrinkStoredFiles(in directory: URL) {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        for file in files {
            guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > keepOriginalBytes * 2,
                  let raw = try? Data(contentsOf: file), SealedStorage.isSealed(raw.prefix(8)) else { continue }
            guard let data = try? SealedStorage.open(raw), let small = normalized(data), small.count < data.count,
                  let sealed = try? SealedStorage.seal(small) else {
                // Not an icon we can read or reduce: drop it, the page fetches its icon again.
                try? FileManager.default.removeItem(at: file)
                continue
            }
            try? sealed.write(to: file, options: .atomic)
        }
    }
}

// MARK: - Pages
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

// MARK: - Appearance
/// Light and dark icons. Two things differ by mode: which icon a site offers (`FaviconScript`), and how an SVG icon
/// with `@media (prefers-color-scheme: …)` rules draws. macOS's SVG renderer ignores those rules (it always draws
/// the light version), so the SVG's text is resolved for the mode before decoding. Stored bytes stay as the site
/// sent them; only decoded images and the page/site "last good icon" entries are kept per mode.
extension FaviconCache {
    /// Memory cache key: decoded images can differ by mode, the stored bytes don't.
    func memoryKey(_ key: String, dark: Bool) -> String { dark ? key + "|dark" : key }

    /// The page/site entry for one mode. Entries saved before modes existed have no suffix and are read as a fallback.
    static func modeKey(_ key: String, dark: Bool) -> String { key + (dark ? "|dark" : "|light") }

    /// Decodes icon bytes for a mode. Only SVGs that style themselves by color scheme decode differently.
    nonisolated static func decode(_ data: Data, dark: Bool) -> NSImage? {
        guard let text = String(data: data, encoding: .utf8), text.range(of: "prefers-color-scheme", options: .caseInsensitive) != nil,
              text.drop(while: { $0.isWhitespace || $0 == "\u{FEFF}" }).first == "<" else { return NSImage(data: data) }
        return NSImage(data: Data(resolvingColorScheme(text, dark: dark).utf8))
    }

    /// Unwraps the `@media (prefers-color-scheme: …)` blocks that match the mode and drops the rest.
    nonisolated static func resolvingColorScheme(_ text: String, dark: Bool) -> String {
        var output = ""
        var rest = text[...]
        while let media = rest.range(of: "@media", options: .caseInsensitive),
              let open = rest[media.upperBound...].firstIndex(of: "{") {
            let condition = rest[media.upperBound..<open].lowercased()
            output += rest[..<media.lowerBound]
            guard condition.contains("prefers-color-scheme") else {
                output += rest[media.lowerBound...open]
                rest = rest[rest.index(after: open)...]
                continue
            }
            // The block's matching brace; an unbalanced block leaves the rest as it is.
            var depth = 0, close: Substring.Index?
            var index = open
            while index < rest.endIndex {
                if rest[index] == "{" { depth += 1 } else if rest[index] == "}" { depth -= 1; if depth == 0 { close = index; break } }
                index = rest.index(after: index)
            }
            guard let close else { output += rest[media.lowerBound...]; return output }
            if condition.contains("dark") == dark { output += rest[rest.index(after: open)..<close] }
            rest = rest[rest.index(after: close)...]
        }
        return output + rest
    }
}
