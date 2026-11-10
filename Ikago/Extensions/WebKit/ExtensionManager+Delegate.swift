import AppKit
import WebKit

/// What extensions can ask of the browser: windows, new tabs, options pages, popups and
/// extra permissions. Ikago has one window, so "new windows" become tabs in it.
extension ExtensionManager: WKWebExtensionControllerDelegate {
    func webExtensionController(_ controller: WKWebExtensionController,
                                openWindowsFor extensionContext: WKWebExtensionContext) -> [any WKWebExtensionWindow] {
        browser.map { [$0] } ?? []
    }

    func webExtensionController(_ controller: WKWebExtensionController,
                                focusedWindowFor extensionContext: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        browser?.window?.isKeyWindow == true ? browser : nil
    }

    func webExtensionController(_ controller: WKWebExtensionController,
                                openNewTabUsing configuration: WKWebExtension.TabConfiguration,
                                for extensionContext: WKWebExtensionContext,
                                completionHandler: @escaping ((any WKWebExtensionTab)?, (any Error)?) -> Void) {
        guard let browser else { return completionHandler(nil, Self.error("No browser window")) }
        let tab = browser.openTabForExtension(url: configuration.url?.absoluteString ?? "about:blank",
                                              active: configuration.shouldBeActive,
                                              pinned: configuration.shouldBePinned)
        completionHandler(tab, nil)
    }

    func webExtensionController(_ controller: WKWebExtensionController,
                                openNewWindowUsing configuration: WKWebExtension.WindowConfiguration,
                                for extensionContext: WKWebExtensionContext,
                                completionHandler: @escaping ((any WKWebExtensionWindow)?, (any Error)?) -> Void) {
        guard let browser else { return completionHandler(nil, Self.error("No browser window")) }
        for url in configuration.tabURLs {
            browser.openTabForExtension(url: url.absoluteString, active: configuration.shouldBeFocused, pinned: false)
        }
        completionHandler(browser, nil)
    }

    func webExtensionController(_ controller: WKWebExtensionController,
                                openOptionsPageFor extensionContext: WKWebExtensionContext,
                                completionHandler: @escaping ((any Error)?) -> Void) {
        guard let browser, let url = extensionContext.optionsPageURL else {
            return completionHandler(Self.error("No options page"))
        }
        browser.openTabForExtension(url: url.absoluteString, active: true, pinned: false)
        completionHandler(nil)
    }

    func webExtensionController(_ controller: WKWebExtensionController,
                                promptForPermissions permissions: Set<WKWebExtension.Permission>,
                                in tab: (any WKWebExtensionTab)?, for extensionContext: WKWebExtensionContext,
                                completionHandler: @escaping (Set<WKWebExtension.Permission>, Date?) -> Void) {
        let abilities = ExtensionPrompts.describe(permissions: permissions, patterns: [])
        Task {
            let ok = await ExtensionPrompts.confirmMore(name(extensionContext),
                                                        abilities: abilities.isEmpty ? permissions.map(\.rawValue) : abilities,
                                                        in: browser?.window)
            completionHandler(ok ? permissions : [], nil)
        }
    }

    func webExtensionController(_ controller: WKWebExtensionController,
                                promptForPermissionToAccess urls: Set<URL>,
                                in tab: (any WKWebExtensionTab)?, for extensionContext: WKWebExtensionContext,
                                completionHandler: @escaping (Set<URL>, Date?) -> Void) {
        let hosts = Set(urls.compactMap(\.host)).sorted()
        Task {
            let ok = await ExtensionPrompts.confirmMore(name(extensionContext),
                                                        abilities: ["Read and change your data on \(hosts.joined(separator: ", "))"],
                                                        in: browser?.window)
            completionHandler(ok ? urls : [], nil)
        }
    }

    func webExtensionController(_ controller: WKWebExtensionController,
                                promptForPermissionMatchPatterns matchPatterns: Set<WKWebExtension.MatchPattern>,
                                in tab: (any WKWebExtensionTab)?, for extensionContext: WKWebExtensionContext,
                                completionHandler: @escaping (Set<WKWebExtension.MatchPattern>, Date?) -> Void) {
        let abilities = ExtensionPrompts.describe(permissions: [], patterns: matchPatterns)
        Task {
            let ok = await ExtensionPrompts.confirmMore(name(extensionContext), abilities: abilities, in: browser?.window)
            completionHandler(ok ? matchPatterns : [], nil)
        }
    }

    func webExtensionController(_ controller: WKWebExtensionController, didUpdate action: WKWebExtension.Action,
                                forExtensionContext context: WKWebExtensionContext) {
        actionDidChange()
    }

    /// Shows WebKit's own popover for the action, under the extension's toolbar button.
    func webExtensionController(_ controller: WKWebExtensionController, presentActionPopup action: WKWebExtension.Action,
                                for context: WKWebExtensionContext,
                                completionHandler: @escaping ((any Error)?) -> Void) {
        guard let popover = action.popupPopover else { return completionHandler(Self.error("No popup")) }
        let anchor = [anchors[context.uniqueIdentifier], anchors["address"], browser?.window?.contentView]
            .compactMap { $0 }.first { $0.window != nil }
        guard let anchor, anchor.window != nil else { return completionHandler(Self.error("No anchor")) }
        presentedPopover?.close()
        presentedPopover = popover
        popover.behavior = .transient
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
        completionHandler(nil)
    }

    private func name(_ context: WKWebExtensionContext) -> String {
        context.webExtension.displayName ?? "An extension"
    }

    nonisolated static func error(_ message: String) -> NSError {
        NSError(domain: "Ikago.Extensions", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
