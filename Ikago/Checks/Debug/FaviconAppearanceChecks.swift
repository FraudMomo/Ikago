#if DEBUG
import AppKit

/// Light and dark icons: SVG color-scheme styles, a site's per-mode `<link>`s, and per-mode remembered icons.
@MainActor
enum FaviconAppearanceChecks {
    static func run(_ browser: BrowserWindowController) async {
        var failures = 0
        func check(_ value: Bool, _ title: String) {
            print("IKTEST faviconappearance \(value ? "PASS" : "FAIL") \(title)")
            if !value { failures += 1 }
        }
        let cache = FaviconCache.shared
        let saved = cache.dark
        defer { cache.dark = saved }

        // SVG: macOS ignores prefers-color-scheme, so the text is resolved for the mode before decoding.
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16"><style>rect{fill:#ff0000}\
        @media (prefers-color-scheme: dark){rect{fill:#00ff00}}</style><rect width="16" height="16"/></svg>
        """
        func green(_ image: NSImage?) -> Bool? {
            guard let image, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
            let color = NSBitmapImageRep(cgImage: cg).colorAt(x: cg.width / 2, y: cg.height / 2)?.usingColorSpace(.deviceRGB)
            return color.map { $0.greenComponent > $0.redComponent + 0.2 }
        }
        let data = Data(svg.utf8)
        check(green(FaviconCache.decode(data, dark: true)) == true, "SVG draws its dark style in dark mode")
        check(green(FaviconCache.decode(data, dark: false)) == false, "SVG draws its light style in light mode")
        let nested = FaviconCache.resolvingColorScheme("a@media (prefers-color-scheme: light){b{c}}d@media print{e}", dark: true)
        check(nested == "ad@media print{e}", "only color-scheme blocks are resolved, other @media rules stay")

        // A site offering an icon per mode: the picker follows Ikago's mode.
        let file = SessionStore.testDirectory.appending(path: "favicon-modes.html")
        let html = """
        <!doctype html><title>Modes</title>
        <link rel="icon" href="https://modes.invalid/light.png" media="(prefers-color-scheme: light)">
        <link rel="icon" href="https://modes.invalid/dark.png" media="(prefers-color-scheme: dark)">
        <link rel="icon" href="https://modes.invalid/plain.png">
        """
        try? html.write(to: file, atomically: true, encoding: .utf8)
        browser.open(file.absoluteString, inNewTab: true)
        try? await Task.sleep(for: .milliseconds(700))
        if let page = browser.activeController?.page {
            let darkPick = try? await page.evaluate(FaviconScript.pick(dark: true)) as? String
            let lightPick = try? await page.evaluate(FaviconScript.pick(dark: false)) as? String
            check(darkPick == "https://modes.invalid/dark.png", "dark mode picks the site's dark icon")
            check(lightPick == "https://modes.invalid/light.png", "light mode picks the site's light icon")
            if let id = browser.state.activeTabID { browser.closeTab(id) }
        } else { check(false, "fixture page opens") }

        // Remembered icons are kept per mode, so switching modes never shows the other mode's icon.
        let page = "https://mode-cache.invalid/\(UUID())"
        func icon(_ color: NSColor) -> (NSImage, Data) {
            let image = NSImage(size: NSSize(width: 16, height: 16))
            image.lockFocus(); color.setFill(); NSRect(x: 0, y: 0, width: 16, height: 16).fill(); image.unlockFocus()
            return (image, NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!)
        }
        let light = URL(string: page + "/light.png")!, dark = URL(string: page + "/dark.png")!
        let (lightImage, lightData) = icon(.red), (darkImage, darkData) = icon(.green)
        cache.storeCached(lightImage, data: lightData, key: light.absoluteString, dark: false)
        cache.storeCached(darkImage, data: darkData, key: dark.absoluteString, dark: true)
        _ = await cache.image(pageURL: page, iconURL: light, dark: false)
        _ = await cache.image(pageURL: page, iconURL: dark, dark: true)
        check(green(cache.cachedImage(pageURL: page, iconURL: light, dark: true)) == true,
              "dark mode shows the page's dark icon even when the tab last reported its light one")
        check(green(cache.cachedImage(pageURL: page, iconURL: dark, dark: false)) == false,
              "light mode shows the page's light icon even when the tab last reported its dark one")
        print("IKTEST faviconappearancechecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }
}
#endif
