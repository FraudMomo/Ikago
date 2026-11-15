import AppKit
import ImageIO
import Observation

/// Album art for the media island, from Media Session metadata, a media poster or the page's thumbnail.
///
/// Loaded the way Ikago loads favicons: an ephemeral session without cookies, a size cap, and only raster formats sites
/// use, because decoding happens in the main process. Downsampled to 160 px and kept in memory only.
@MainActor @Observable
final class MediaArtwork {
    static let shared = MediaArtwork()

    struct Art {
        let image: NSImage
    }

    private(set) var images: [URL: Art] = [:]
    @ObservationIgnored private var loading: Set<URL> = []
    @ObservationIgnored private var order: [URL] = []
    private static let maxBytes = 4 << 20
    private static let keep = 24

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 15
        return URLSession(configuration: configuration)
    }()

    func art(for url: URL?) -> Art? {
        guard let url else { return nil }
        if let art = images[url] { return art }
        load(url)
        return nil
    }

    private func load(_ url: URL) {
        guard url.scheme == "https", !loading.contains(url) else { return }
        loading.insert(url)
        Task {
            defer { loading.remove(url) }
            guard let (data, response) = try? await Self.session.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200, data.count <= Self.maxBytes,
                  Self.isRaster(data),
                  let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 160,
                    kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary) else { return }
            images[url] = Art(image: NSImage(cgImage: thumbnail, size: .zero))
            order.append(url)
            if order.count > Self.keep { images[order.removeFirst()] = nil }
        }
    }

    /// PNG, JPEG, GIF or WebP: what sites serve as artwork. No SVG or other formats.
    nonisolated static func isRaster(_ data: Data) -> Bool {
        let bytes = [UInt8](data.prefix(12))
        func starts(_ prefix: [UInt8]) -> Bool { bytes.starts(with: prefix) }
        if starts([0x89, 0x50, 0x4E, 0x47]) || starts([0xFF, 0xD8, 0xFF]) || starts([0x47, 0x49, 0x46, 0x38]) { return true }
        return bytes.count == 12 && starts([0x52, 0x49, 0x46, 0x46]) && Array(bytes[8..<12]) == Array("WEBP".utf8)
    }
}
