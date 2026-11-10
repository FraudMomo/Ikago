import AppKit
import WebKit

/// Native sheets for extension installs and runtime permission requests.
/// Fail-closed: closing or cancelling a prompt denies.
@MainActor
enum ExtensionPrompts {
    /// `webKitNotes`: WebKit's compatibility notes, which don't apply when Chromium runs the extension.
    static func confirmInstall(_ ext: WKWebExtension, in window: NSWindow?, webKitNotes: Bool = true) async -> Bool {
        #if DEBUG
        if WebProfiles.isTestMode, DebugEnvironment.value("IKAGO_TEST_AUTO_APPROVE") != nil { return true }
        #endif
        let alert = NSAlert()
        alert.messageText = "Add “\(ext.displayName ?? "extension")” to Ikago?"
        let abilities = describe(permissions: ext.requestedPermissions, patterns: ext.requestedPermissionMatchPatterns)
        alert.informativeText = abilities.isEmpty
            ? "It doesn't request any special permissions."
            : "It can:\n" + abilities.map { "• \($0)" }.joined(separator: "\n")
        let warnings = ExtensionCompatibility.warnings(manifest: ext.manifest)
        if webKitNotes, !warnings.isEmpty { alert.informativeText += "\n\nLimited support:\n" + warnings.joined(separator: "\n") }
        alert.icon = ext.icon(for: CGSize(width: 64, height: 64))
        alert.addButton(withTitle: "Add Extension")
        alert.addButton(withTitle: "Cancel")
        return await run(alert, in: window) == .alertFirstButtonReturn
    }

    /// A loaded extension asks for more access at runtime (optional permissions).
    static func confirmMore(_ name: String, abilities: [String], in window: NSWindow?) async -> Bool {
        let alert = NSAlert()
        alert.messageText = "“\(name)” wants additional access"
        alert.informativeText = abilities.map { "• \($0)" }.joined(separator: "\n")
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Don't Allow")
        return await run(alert, in: window) == .alertFirstButtonReturn
    }

    private static func run(_ alert: NSAlert, in window: NSWindow?) async -> NSApplication.ModalResponse {
        if let window, window.attachedSheet == nil { return await alert.beginSheetModal(for: window) }
        return alert.runModal()
    }

    // MARK: Plain-language permissions

    static func describe(permissions: Set<WKWebExtension.Permission>,
                         patterns: Set<WKWebExtension.MatchPattern>) -> [String] {
        var lines: [String] = []
        if patterns.contains(where: \.matchesAllHosts) {
            lines.append("Read and change your data on all websites")
        } else if !patterns.isEmpty {
            let hosts = patterns.compactMap(\.host).sorted()
            lines.append("Read and change your data on \(ListFormatter.localizedString(byJoining: hosts))")
        }
        let known: [WKWebExtension.Permission: String] = [
            .tabs: "See your open tabs and their addresses",
            .cookies: "Read and change cookies",
            .clipboardWrite: "Write to the clipboard",
            .declarativeNetRequest: "Block or change content on pages you visit",
            .declarativeNetRequestWithHostAccess: "Block or change content on pages you visit",
            .webNavigation: "See the pages you visit",
            .nativeMessaging: "Talk to apps installed on your Mac",
            .scripting: "Run scripts on pages it has access to",
        ]
        for (permission, text) in known where permissions.contains(permission) && !lines.contains(text) {
            lines.append(text)
        }
        return lines
    }
}
