import AppKit

/// The Mac's own light/dark setting, for Ikago's System mode. Read from macOS's setting, not `NSApp.effectiveAppearance`:
/// Ikago sets the app's appearance to its own mode (`ChromiumAppearance`), so the app's effective appearance would
/// report Ikago's choice back as the system's.
@MainActor
final class SystemAppearance {
    private var observer: NSObjectProtocol?

    static var isDark: Bool { UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark" }

    /// Calls `changed` now and whenever the Mac switches between light and dark (including Auto).
    init(_ changed: @escaping @MainActor (Bool) -> Void) {
        changed(Self.isDark)
        observer = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { changed(SystemAppearance.isDark) }
        }
    }

    isolated deinit {
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
    }
}
