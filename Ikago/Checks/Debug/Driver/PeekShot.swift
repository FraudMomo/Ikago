#if DEBUG
import AppKit
import Darwin

/// Reads what a page really drew: captures the window (its own, no permission needed) and finds where a red strip at
/// the page's top and a blue strip at its bottom appear, against the page view's own edges.
@MainActor
enum PeekShot {
    static func measure(_ view: NSView, window: NSWindow?, save: String?) -> String {
        guard let window, let content = window.contentView else { return "no-window" }
        typealias Capture = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { return "no-capture-api" }
        guard let image = unsafeBitCast(symbol, to: Capture.self)(.null, 8, UInt32(window.windowNumber), 1 | 16)?.takeRetainedValue()
        else { return "no-image" }
        let bitmap = NSBitmapImageRep(cgImage: image)
        if let save { try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: save)) }
        let scale = CGFloat(bitmap.pixelsWide) / content.bounds.width
        let rect = content.convert(view.bounds, from: view)
        let x = Int(rect.midX * scale), top = Int((content.bounds.height - rect.maxY) * scale), height = Int(rect.height * scale)
        func kind(_ row: Int) -> Character {
            guard let c = bitmap.colorAt(x: x, y: max(0, min(bitmap.pixelsHigh - 1, row)))?.usingColorSpace(.sRGB) else { return "?" }
            if c.redComponent > 0.75 && c.greenComponent < 0.35 && c.blueComponent < 0.35 { return "R" }
            if c.blueComponent > 0.75 && c.redComponent < 0.35 { return "B" }
            return "."
        }
        let red = (0..<height).first { kind(top + $0) == "R" }.map { Int(CGFloat($0) / scale) }
        let blue = (0..<height).last { kind(top + $0) == "B" }.map { Int(CGFloat(height - 1 - $0) / scale) }
        return "redStartsBelowTop=\(red.map(String.init) ?? "none") blueEndsAboveBottom=\(blue.map(String.init) ?? "none") view=\(NSStringFromRect(rect))"
    }
}
#endif
