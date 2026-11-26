import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Ikago Home's own background: the page colour, a colour the person picks, or an image of theirs, optionally blurred
/// (`BrowserPreferences.homeBackgroundColor`, `homeBackgroundImage`, `homeBackgroundBlur`). The image is copied into the
/// profile folder, downscaled, so the original can move or go.
@MainActor
enum HomeBackground {
    static var file: URL { SessionStore.standard.directory.appending(path: "home-background.jpg") }
    private static var cached: (date: Date, image: NSImage)?

    /// The saved image, read once per change of the file.
    static var image: NSImage? {
        guard let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else { return nil }
        if let cached, cached.date == date { return cached.image }
        guard let image = NSImage(contentsOf: file) else { return nil }
        cached = (date, image)
        return image
    }

    /// Copies an image the person chose, at most 2560 pt on its long side, as JPEG. False if it isn't an image.
    static func save(from source: URL) -> Bool {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let reader = CGImageSourceCreateWithURL(source as CFURL, options),
              let image = CGImageSourceCreateThumbnailAtIndex(reader, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 2560,
              ] as CFDictionary) else { return false }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let writer = CGImageDestinationCreateWithURL(file as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(writer, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(writer) else { return false }
        cached = nil
        return true
    }

    static func remove() {
        try? FileManager.default.removeItem(at: file)
        cached = nil
    }

    /// Asks for an image and uses it. Returns false when the person cancelled or it couldn't be read.
    static func choose() -> Bool {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a picture for Ikago Home"
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        return save(from: url)
    }
}

/// What lies behind Ikago Home's tiles.
struct HomeBackdrop: View {
    let state: BrowserState
    /// Bumped when the image changes, so it's read again.
    let version: Int

    var body: some View {
        let prefs = state.browserPreferences
        let blur = prefs.homeBackgroundBlur == true
        ZStack {
            state.palette.pageBackground
            if prefs.homeBackgroundImage == true, version >= 0, let image = HomeBackground.image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    .blur(radius: blur ? 28 : 0, opaque: true)
                    // A light veil in the page's mode keeps the names readable over any picture.
                    .overlay(state.palette.pageBackground.opacity(blur ? 0.2 : 0.3))
            } else if let hex = prefs.homeBackgroundColor {
                Color(hex: hex)
                if blur { Rectangle().fill(.regularMaterial).opacity(0.5) }
            }
        }
        .clipped()
        .ignoresSafeArea()
    }
}
