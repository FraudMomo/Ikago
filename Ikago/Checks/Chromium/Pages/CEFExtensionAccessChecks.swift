import AppKit
import IKCEFBridge

/// Website access on Chromium, through the same extension-service calls `ChromiumExtensions+Access` makes: an extension
/// limited to specific sites stays off a page until that site is granted, and runs once it is.
@MainActor
enum CEFExtensionAccessChecks {
    static func run(manager: IKCEFPage, browser: IKCEFPage) async throws {
        print("CEF_SMOKE_STAGE extension-access")
        let id = try await value(manager, """
            chrome.developerPrivate.getExtensionsInfo({includeDisabled: true}).then(items => {
              const item = items.find(x => x.name === 'Ikago Fixture'); return item ? item.id : null })
            """) as? String
        guard let id else { throw CEFError.script("The fixture extension is missing.") }
        let quoted = ChromiumExtensions.json(id)
        let access = try await value(manager, """
            chrome.developerPrivate.getExtensionsInfo({includeDisabled: true}).then(items =>
              (items.find(x => x.id === \(quoted)).permissions.runtimeHostPermissions || {}).hostAccess || null)
            """) as? String
        guard access != nil else { throw CEFError.script("Chromium reports no site access for the fixture.") }
        _ = try await value(manager, "chrome.developerPrivate.updateExtensionConfiguration({extensionId: \(quoted), hostAccess: 'ON_SPECIFIC_SITES'})")
        try await reload(browser)
        if await marker(browser) == "active" {
            throw CEFError.script("An extension limited to specific sites still ran on an ungranted site.")
        }
        let pattern = ExtensionAccess.pattern(for: "127.0.0.1")
        _ = try await value(manager, "chrome.developerPrivate.addHostPermission(\(quoted), \(ChromiumExtensions.json(pattern)))")
        let granted = try await value(manager, """
            chrome.developerPrivate.getExtensionsInfo({includeDisabled: true}).then(items =>
              items.find(x => x.id === \(quoted)).permissions.runtimeHostPermissions.hosts.filter(h => h.granted).map(h => h.host))
            """) as? [String] ?? []
        guard granted.contains(pattern) else { throw CEFError.script("Granted hosts read back as \(granted), not \(pattern).") }
        try await reload(browser)
        var active = false
        for _ in 0..<50 where !active {
            active = await marker(browser) == "active"
            if !active { try await Task.sleep(for: .milliseconds(100)) }
        }
        guard active else {
            throw CEFError.script("A granted site didn't get the extension.")
        }
        _ = try await value(manager, "chrome.developerPrivate.removeHostPermission(\(quoted), \(ChromiumExtensions.json(pattern)))")
        _ = try await value(manager, "chrome.developerPrivate.updateExtensionConfiguration({extensionId: \(quoted), hostAccess: 'ON_ALL_SITES'})")
        print("CEF_EXTENSION_ACCESS_OK specific-sites grant read-back")
    }

    /// Reloads and waits until the new document answers scripts.
    private static func reload(_ page: IKCEFPage) async throws {
        page.reloadIgnoringCache(false)
        try await Task.sleep(for: .milliseconds(300))
        for _ in 0..<50 {
            if (try? await value(page, "document.readyState")) as? String == "complete" { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        try await Task.sleep(for: .milliseconds(300))
    }

    /// The fixture's content-script mark, once the page answers.
    private static func marker(_ page: IKCEFPage) async -> String {
        for _ in 0..<20 {
            if let mark = (try? await value(page, "document.documentElement.dataset.ikagoExtensionFixture || ''")) as? String { return mark }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return "?"
    }

    private static func value(_ page: IKCEFPage, _ expression: String) async throws -> Any? {
        let result = try await CEFSmoke.method(page, "Runtime.evaluate", ["expression": expression, "returnByValue": true, "awaitPromise": true])
        if let exception = result["exceptionDetails"] as? [String: Any] {
            throw CEFError.script("Script failed: \(exception["exception"].flatMap { ($0 as? [String: Any])?["description"] } ?? exception)")
        }
        return (result["result"] as? [String: Any])?["value"]
    }
}
