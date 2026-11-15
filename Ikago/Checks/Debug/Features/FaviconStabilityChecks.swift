#if DEBUG
import AppKit
import SwiftUI

@MainActor
enum FaviconStabilityChecks {
    static func run(_ browser: BrowserWindowController) async {
        var failures = 0
        func check(_ value: Bool, _ title: String) {
            print("IKTEST faviconstability \(value ? "PASS" : "FAIL") \(title)")
            if !value { failures += 1 }
        }
        let cache = FaviconCache.shared
        check(!FaviconCache.hasOwnIcon("about:blank") && !FaviconCache.hasOwnIcon("about:newtab") && !FaviconCache.hasOwnIcon("data:text/html,x"),
              "blank and hostless pages never share a remembered icon")
        check(FaviconCache.hasOwnIcon("https://chatgpt.com/") && FaviconCache.hasOwnIcon("chrome-extension://abc/index.html"),
              "sites and extension pages keep theirs")
        let page = "https://stable-icon.invalid/\(UUID())"
        let old = URL(string: page + "/good.png")!, next = URL(string: page + "/next.png")!
        let broken = URL(fileURLWithPath: "/missing-favicon.png")
        func icon(_ color: NSColor) -> NSImage {
            let image = NSImage(size: NSSize(width: 16, height: 16))
            image.lockFocus(); color.setFill(); NSRect(x: 0, y: 0, width: 16, height: 16).fill(); image.unlockFocus()
            return image
        }
        let red = icon(.red), blue = icon(.blue)
        cache.storeCached(red, data: red.tiffRepresentation!, key: old.absoluteString)
        _ = await cache.image(pageURL: page, iconURL: old)
        check(cache.cachedImage(pageURL: page, iconURL: broken) != nil, "unknown replacement URL retains last-known-good page icon synchronously")
        check(await cache.image(pageURL: page, iconURL: broken) != nil, "failed replacement preserves the working icon")
        check(cache.cachedImage(pageURL: page + "/other", iconURL: nil) != nil, "same-site navigation keeps a known icon before new metadata arrives")
        for pass in 1...3 {
            let view = NSHostingView(rootView: FaviconView(pageURL: page, iconURL: broken.absoluteString, size: 24).frame(width: 32, height: 32))
            view.frame = NSRect(x: 0, y: 0, width: 32, height: 32)
            view.layoutSubtreeIfNeeded()
            var redPixels = 0
            if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                for x in 0..<rep.pixelsWide {
                    for y in 0..<rep.pixelsHigh {
                        if let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                           color.redComponent > 0.8, color.greenComponent < 0.2, color.blueComponent < 0.2 { redPixels += 1 }
                    }
                }
            }
            check(redPixels > 100, "recreated favicon view \(pass) renders its saved image immediately")
        }
        cache.storeCached(blue, data: blue.tiffRepresentation!, key: next.absoluteString)
        let updated = await cache.image(pageURL: page, iconURL: next)
        check(updated === blue, "successful replacement updates the cached page icon")
        let original = browser.state.snapshot()
        defer { browser.state.apply(original) }
        let tab = browser.state.newTab(url: page)!
        tab.faviconURL = old
        browser.state.togglePin(tab.id)
        let controller = browser.content.ensureController(for: tab)!
        controller.startIfNeeded()
        if let web = controller.page {
            controller.webTab(web, didFindFavicon: broken)
            try? await Task.sleep(for: .milliseconds(100))
            check(tab.faviconURL == old, "failed page-reported favicon cannot overwrite the tab's saved icon URL")
        } else { check(false, "missing fixture web view") }
        browser.closeTab(tab.id)
        browser.state.select(tab.id)
        try? await Task.sleep(for: .milliseconds(300))
        check(tab.faviconURL == old && cache.cachedImage(for: old) != nil, "pin unload and wake retain the saved URL and icon bytes")
        print("IKTEST faviconstabilitychecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }
}
#endif
