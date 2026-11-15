import AppKit
import SwiftUI

/// A browser's own app icon, read from the installed app; a globe when the app isn't installed.
/// Icons come from the system at run time, so no other browser's artwork ships with Ikago.
struct BrowserLogo: View {
    let browser: String
    var size: CGFloat = 28

    var body: some View {
        if let icon = Self.icon(for: browser) {
            Image(nsImage: icon).resizable().interpolation(.high).frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            Image(systemName: browser == "exported file" ? "doc" : "globe")
                .font(.system(size: size * 0.5, weight: .medium)).foregroundStyle(.secondary)
                .frame(width: size, height: size).background(Circle().fill(Color.primary.opacity(0.07)))
                .accessibilityHidden(true)
        }
    }

    @MainActor private static var cache: [String: NSImage] = [:]

    @MainActor static func icon(for browser: String) -> NSImage? {
        if let cached = cache[browser] { return cached }
        guard let bundle = BrowserProfileDiscovery.bundleIDs[browser],
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        cache[browser] = icon
        return icon
    }
}
