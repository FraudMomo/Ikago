import AppKit

/// The Finder-visible half of a web app: a tiny app bundle in ~/Applications whose only job is to ask Ikago to open
/// the app (`ikago-app://<id>`). It has no Dock icon of its own while it runs; pinned, it stays in the Dock as the app's
/// shortcut, and shows in Launchpad and Spotlight with the site's icon.
enum WebAppLauncher {
    static var folder: URL { FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications", directoryHint: .isDirectory) }

    static func url(for app: WebApp, in folder: URL = WebAppLauncher.folder) -> URL {
        let safe = app.name.components(separatedBy: CharacterSet(charactersIn: "/:\\\n\r\t")).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return folder.appending(path: "\(safe.isEmpty ? "Web App" : String(safe.prefix(60))).app", directoryHint: .isDirectory)
    }

    /// Writes (or replaces) the launcher; returns where it is.
    @discardableResult
    static func write(_ app: WebApp, icon: NSImage?, in folder: URL = WebAppLauncher.folder) throws -> URL {
        // The ID is written into the launcher's shell script, so it must be nothing but an identifier.
        guard !app.id.isEmpty, app.id.count <= 64, app.id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        let bundle = url(for: app, in: folder)
        let manager = FileManager.default
        try? manager.removeItem(at: bundle)
        let contents = bundle.appending(path: "Contents", directoryHint: .isDirectory)
        try manager.createDirectory(at: contents.appending(path: "MacOS"), withIntermediateDirectories: true)
        try manager.createDirectory(at: contents.appending(path: "Resources"), withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleIdentifier": "app.ikago.webapp.\(app.id)", "CFBundleName": app.name, "CFBundleDisplayName": app.name,
            "CFBundleExecutable": "launcher", "CFBundleIconFile": "icon", "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.0", "CFBundleVersion": "1", "LSUIElement": true,
            "LSMinimumSystemVersion": "13.0", "NSHighResolutionCapable": true,
        ]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appending(path: "Info.plist"))
        let script = contents.appending(path: "MacOS/launcher")
        try "#!/bin/sh\nexec /usr/bin/open \"\(app.launchURL)\"\n".write(to: script, atomically: true, encoding: .utf8)
        try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        try WebAppIcon.icns(for: app, favicon: icon).write(to: contents.appending(path: "Resources/icon.icns"))
        // Launch Services learns of the new app, and Finder redraws its icon.
        NSWorkspace.shared.noteFileSystemChanged(bundle.path)
        return bundle
    }

    static func remove(_ app: WebApp) { try? FileManager.default.trashItem(at: url(for: app), resultingItemURL: nil) }
}

/// The launcher's icon: the site's own icon on a white tile, or its first letter on a colored one.
enum WebAppIcon {
    static func icns(for app: WebApp, favicon: NSImage?) throws -> Data {
        // The macOS icon grid: the tile fills 824 of the 1024 points.
        func render(_ side: Int) -> Data? {
            let size = NSSize(width: side, height: side)
            let image = NSImage(size: size, flipped: false) { rect in
                let scale = CGFloat(side) / 1024
                let tile = NSRect(x: 100 * scale, y: 100 * scale, width: 824 * scale, height: 824 * scale)
                let path = NSBezierPath(roundedRect: tile, xRadius: 185 * scale, yRadius: 185 * scale)
                NSGraphicsContext.saveGraphicsState()
                let shadow = NSShadow()
                shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
                shadow.shadowBlurRadius = 16 * scale
                shadow.shadowOffset = NSSize(width: 0, height: -10 * scale)
                shadow.set()
                (favicon == nil ? tint(app) : NSColor.white).setFill()
                path.fill()
                NSGraphicsContext.restoreGraphicsState()
                if let favicon {
                    let inner = tile.insetBy(dx: 210 * scale, dy: 210 * scale)
                    favicon.draw(in: inner, from: .zero, operation: .sourceOver, fraction: 1)
                } else {
                    let letter = String(app.name.first(where: \.isLetter) ?? app.name.first ?? "W").uppercased() as NSString
                    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 430 * scale, weight: .semibold), .foregroundColor: NSColor.white]
                    let box = letter.size(withAttributes: attributes)
                    letter.draw(at: NSPoint(x: tile.midX - box.width / 2, y: tile.midY - box.height / 2), withAttributes: attributes)
                }
                return true
            }
            guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
            return bitmap.representation(using: .png, properties: [:])
        }
        // An .icns is a header and typed PNG entries: 128, 256, 512 and 1024 points.
        var body = Data()
        for (type, side) in [("ic07", 128), ("ic08", 256), ("ic09", 512), ("ic10", 1024)] {
            guard let png = render(side) else { throw CocoaError(.fileWriteUnknown) }
            body.append(Data(type.utf8))
            body.append(bigEndian: UInt32(png.count + 8))
            body.append(png)
        }
        var data = Data("icns".utf8)
        data.append(bigEndian: UInt32(body.count + 8))
        data.append(body)
        return data
    }

    private static func tint(_ app: WebApp) -> NSColor {
        let hue = Double(abs(app.host.unicodeScalars.reduce(7) { ($0 &* 31) &+ Int($1.value) }) % 360) / 360
        return NSColor(hue: hue, saturation: 0.55, brightness: 0.72, alpha: 1)
    }
}

private extension Data {
    mutating func append(bigEndian value: UInt32) {
        var big = value.bigEndian
        Swift.withUnsafeBytes(of: &big) { append(contentsOf: $0) }
    }
}
