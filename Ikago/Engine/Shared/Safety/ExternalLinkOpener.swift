import AppKit
import WebKit

/// Routes desktop-app URLs without passing them to WebKit or changing the browser's page.
@MainActor
final class ExternalLinkOpener {
    typealias Confirmation = (String, String, NSWindow) async -> Bool
    private let application: (URL) -> URL?
    private let confirm: Confirmation
    private let launch: (URL, URL) async throws -> Void
    private var opening = false

    init(application: @escaping (URL) -> URL? = { NSWorkspace.shared.urlForApplication(toOpen: $0) },
         confirm: @escaping Confirmation = ExternalLinkOpener.confirm,
         launch: @escaping (URL, URL) async throws -> Void = { url, app in
             guard !WebProfiles.isTestMode else { throw CocoaError(.userCancelled) }
             _ = try await NSWorkspace.shared.open([url], withApplicationAt: app, configuration: .init())
         }) {
        self.application = application; self.confirm = confirm; self.launch = launch
    }

    static func isExternal(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), !scheme.isEmpty else { return false }
        return !["http", "https", "file", "about", "blob", "data", "javascript",
                 "ikago", "chrome-extension", "webkit-extension"].contains(scheme)
    }

    static func permits(_ action: WKNavigationAction) -> Bool {
        // OAuth callbacks and scripted "Open in app" buttons use .other. Hidden frames
        // still need an actual link activation; top-level redirects always ask the user.
        action.navigationType == .linkActivated || action.targetFrame?.isMainFrame != false
    }

    func open(_ url: URL, sourceHost: String, in window: NSWindow?) async {
        guard Self.isExternal(url), let window, !opening else { return }
        opening = true
        defer { opening = false }
        let scheme = url.scheme!.lowercased()
        guard let app = application(url) else {
            await showFailure("No application is installed to open “\(scheme)” links.", in: window)
            return
        }
        let name = FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: "")
        guard await confirm(name, sourceHost, window) else { return }
        do {
            // Use the exact URL (including OAuth state/query/fragment) and the app the user approved.
            try await launch(url, app)
        } catch {
            // Callback URLs may contain authentication codes; never log or display them.
            await showFailure("macOS couldn’t open \(name). Try opening the app and following the link again.", in: window)
        }
    }

    private static func confirm(_ name: String, _ host: String, _ window: NSWindow) async -> Bool {
        let alert = NSAlert()
        alert.messageText = host.isEmpty ? "Open “\(name)”?" : "Allow “\(host)” to open “\(name)”?"
        alert.informativeText = "This link opens another application on your Mac."
        alert.addButton(withTitle: "Open \(name)")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[1].keyEquivalent = "\u{1b}"
        return await alert.beginSheetModal(for: window) == .alertFirstButtonReturn
    }

    private func showFailure(_ message: String, in window: NSWindow) async {
        let alert = NSAlert()
        alert.messageText = "Couldn’t open application"
        alert.informativeText = message
        await alert.beginSheetModal(for: window)
    }
}
