import Foundation
import ImageIO
import UniformTypeIdentifiers

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
