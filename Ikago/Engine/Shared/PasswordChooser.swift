import AppKit

/// Which store fills passwords. Apple Passwords works only through WebKit's AutoFill panel.
enum PasswordSource: String {
    case ikago, apple

    /// The source for WebKit pages; Chromium pages always use Ikago's vault.
    @MainActor static var current: PasswordSource {
        guard BrowserRuntime.runs(.webkit) else { return .ikago }
        if let saved = BrowserSecurity.shared.preferences.passwordSource.flatMap(PasswordSource.init(rawValue:)) { return saved }
        return PasswordVault.shared.isEmpty ? .apple : .ikago
    }
}

/// Picks a login from Ikago's vault for the page's site: a native menu of usernames at the pointer
/// (the key was just clicked), then Touch ID for that one password. Engine independent.
@MainActor
enum PasswordChooser {
    /// Whether a page at `url` may show the key: Ikago's vault is in use, the page is HTTPS (or local
    /// development) and something is saved for its site.
    static func offers(for url: URL?, onChromium: Bool = false) -> Bool {
        guard onChromium || PasswordSource.current == .ikago, BrowserSecurity.shared.preferences.passwordAutoFill ?? true,
              let url, let host = url.host else { return false }
        let secure = url.scheme?.lowercased() == "https" || ["localhost", "127.0.0.1", "::1"].contains(host)
        return secure && !PasswordVault.shared.matches(for: host).isEmpty
    }

    /// The page's origin as `location.origin` writes it, so the key script can refuse any other document.
    nonisolated static func origin(of url: URL) -> String {
        let scheme = url.scheme?.lowercased() ?? ""
        var host = url.host?.lowercased() ?? ""
        if host.contains(":") { host = "[" + host + "]" }
        let defaultPort = scheme == "https" ? 443 : scheme == "http" ? 80 : nil
        let port = url.port.flatMap { $0 == defaultPort ? nil : ":\($0)" } ?? ""
        return scheme + "://" + host + port
    }

    /// The chosen login, or nil when the person dismissed the menu or Touch ID.
    static func choose(for url: URL, in view: NSView) async -> (username: String, password: String)? {
        guard offers(for: url), let host = url.host else { return nil }
        let logins = PasswordVault.shared.matches(for: host)
        guard let login = pick(from: logins, in: view) else { return nil }
        do {
            let password = try await PasswordVault.shared.password(for: login, reason: "fill your password for \(PasswordVault.site(host))")
            return (login.username, password)
        } catch {
            if let message = (error as? LocalizedError)?.errorDescription { NSLog("Ikago passwords: %@", message) }
            return nil
        }
    }

    private static func pick(from logins: [PasswordVault.Login], in view: NSView) -> PasswordVault.Login? {
        #if DEBUG || IKAGO_CHECKS
        if SealedStorage.usesTestKey { return logins.first }  // unattended checks can't use a menu
        #endif
        guard let window = view.window else { return nil }
        let menu = NSMenu()
        menu.autoenablesItems = false
        let header = NSMenuItem(title: "Ikago Passwords", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        final class Target: NSObject {
            var chosen: Int?
            @objc func choose(_ item: NSMenuItem) { chosen = item.tag }
        }
        let target = Target()
        // Every match: menus scroll when they don't fit on screen.
        for (index, login) in logins.enumerated() {
            let item = NSMenuItem(title: login.username.isEmpty ? "No username" : login.username,
                                  action: #selector(Target.choose(_:)), keyEquivalent: "")
            item.tag = index
            item.target = target
            item.image = NSImage(systemSymbolName: "key.fill", accessibilityDescription: nil)
            item.subtitle = login.site
            menu.addItem(item)
        }
        let point = view.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        menu.popUp(positioning: nil, at: point, in: view)
        return target.chosen.map { logins[$0] }
    }
}
