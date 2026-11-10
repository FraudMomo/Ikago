// Composites the unchanged character onto a warm off-white macOS tile at every icon size.
// Run from the repository root: swift scripts/make-icon.swift
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let source = root.appending(path: "Ikago/Resources/AppIconSource.png")
let output = root.appending(path: "Ikago/Resources/Assets.xcassets/IkagoAppIcon.appiconset")
guard let image = NSImage(contentsOf: source) else { fatalError("Cannot read \(source.path)") }

func resized(pixels: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let context = NSGraphicsContext(bitmapImageRep: bitmap) else { throw CocoaError(.fileReadCorruptFile) }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    context.cgContext.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
    // Preserve transparent outer corners; the character carries its own soft shadow.
    let unit = CGFloat(pixels) / 1024
    let tile = NSBezierPath()
    tile.move(to: NSPoint(x: 290 * unit, y: 100 * unit))
    tile.line(to: NSPoint(x: 734 * unit, y: 100 * unit))
    tile.curve(to: NSPoint(x: 924 * unit, y: 290 * unit),
               controlPoint1: NSPoint(x: 860 * unit, y: 100 * unit), controlPoint2: NSPoint(x: 924 * unit, y: 164 * unit))
    tile.line(to: NSPoint(x: 924 * unit, y: 734 * unit))
    tile.curve(to: NSPoint(x: 734 * unit, y: 924 * unit),
               controlPoint1: NSPoint(x: 924 * unit, y: 860 * unit), controlPoint2: NSPoint(x: 860 * unit, y: 924 * unit))
    tile.line(to: NSPoint(x: 290 * unit, y: 924 * unit))
    tile.curve(to: NSPoint(x: 100 * unit, y: 734 * unit),
               controlPoint1: NSPoint(x: 164 * unit, y: 924 * unit), controlPoint2: NSPoint(x: 100 * unit, y: 860 * unit))
    tile.line(to: NSPoint(x: 100 * unit, y: 290 * unit))
    tile.curve(to: NSPoint(x: 290 * unit, y: 100 * unit),
               controlPoint1: NSPoint(x: 100 * unit, y: 164 * unit), controlPoint2: NSPoint(x: 164 * unit, y: 100 * unit))
    tile.close()
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.14)
    shadow.shadowBlurRadius = 22 * unit
    shadow.shadowOffset = NSSize(width: 0, height: -12 * unit)
    shadow.set()
    NSColor(srgbRed: 0.94, green: 0.93, blue: 0.91, alpha: 1).setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    tile.addClip()
    // Quiet warm porcelain; depth comes from the character shadow rather than a colored backdrop.
    let surface = NSGradient(colorsAndLocations:
        (NSColor(srgbRed: 0.91, green: 0.90, blue: 0.88, alpha: 1), 0),
        (NSColor(srgbRed: 0.96, green: 0.95, blue: 0.93, alpha: 1), 0.55),
        (NSColor(srgbRed: 0.99, green: 0.985, blue: 0.975, alpha: 1), 1))!
    surface.draw(in: tile, angle: 90)
    let light = NSGradient(starting: NSColor.white.withAlphaComponent(0.35), ending: NSColor.white.withAlphaComponent(0))!
    light.draw(fromCenter: NSPoint(x: 360 * unit, y: 870 * unit), radius: 0,
               toCenter: NSPoint(x: 360 * unit, y: 870 * unit), radius: 760 * unit, options: [.drawsAfterEndingLocation])
    // Fine rim lighting gives the tile depth without adding decorative objects.
    NSColor.white.withAlphaComponent(0.4).setStroke()
    tile.lineWidth = 3 * unit
    tile.stroke()
    NSGraphicsContext.saveGraphicsState()
    let lift = NSShadow()
    lift.shadowColor = NSColor(srgbRed: 0.20, green: 0.16, blue: 0.14, alpha: 0.3)
    lift.shadowBlurRadius = 32 * unit
    lift.shadowOffset = NSSize(width: 4 * unit, height: -18 * unit)
    lift.set()
    // Only placement changes: the master character's shape, colors and detailing remain intact.
    image.draw(in: NSRect(x: 50 * unit, y: 45 * unit, width: 924 * unit, height: 924 * unit),
               from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.restoreGraphicsState()
    for (x, y) in [(0, 0), (pixels - 1, 0), (0, pixels - 1), (pixels - 1, pixels - 1)] {
        guard bitmap.colorAt(x: x, y: y)?.alphaComponent == 0 else {
            fatalError("Every app icon corner must be transparent")
        }
    }
    guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
    return png
}

try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try resized(pixels: points * scale).write(to: output.appending(path: name), options: .atomic)
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: output.appending(path: "Contents.json"), options: .atomic)
print("Wrote \(images.count) Ikago icons from \(source.lastPathComponent)")
