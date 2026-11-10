import AppKit
import SwiftUI

/// Album art for the media island, from the page's Media Session.
///
/// Loaded the way Ikago loads favicons: an ephemeral session without cookies, a size cap, and only raster formats sites
/// use, because decoding happens in the main process. Kept in memory only, so private windows leave nothing behind.
@MainActor @Observable
final class MediaArtwork {
    static let shared = MediaArtwork()

    struct Art {
        let image: NSImage
        /// The image's average color, made vivid enough to draw the wave in, like the Dynamic Island does.
        let glow: Color
        /// False for gray art: no colored light behind the open card.
        let vivid: Bool
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
                  Self.isRaster(data), let image = NSImage(data: data), image.isValid else { return }
            let average = Self.average(of: image)
            images[url] = Art(image: image, glow: Self.vivid(average), vivid: Self.isVivid(average))
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

    private static func average(of image: NSImage) -> NSColor {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 4, bitsPerPixel: 32)
        guard let rep, let context = NSGraphicsContext(bitmapImageRep: rep) else { return .white }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .medium
        image.draw(in: NSRect(x: 0, y: 0, width: 1, height: 1))
        NSGraphicsContext.restoreGraphicsState()
        return rep.colorAt(x: 0, y: 0)?.usingColorSpace(.sRGB) ?? .white
    }

    static func isVivid(_ color: NSColor) -> Bool {
        let c = color.usingColorSpace(.sRGB) ?? color
        return c.saturationComponent > 0.12
    }

    /// The color brightened and saturated to read on black, or white when the art is gray.
    static func vivid(_ color: NSColor) -> Color {
        let c = color.usingColorSpace(.sRGB) ?? color
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        c.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        guard isVivid(c) else { return Color.white.opacity(0.9) }
        return Color(hue: hue, saturation: min(1, max(0.45, saturation * 1.3)), brightness: max(0.85, brightness))
    }
}
