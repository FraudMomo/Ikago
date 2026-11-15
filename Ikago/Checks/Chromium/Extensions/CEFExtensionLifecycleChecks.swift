import Foundation
import IKCEFBridge

@MainActor
enum CEFExtensionLifecycleChecks {
    private static let find = """
    function find(root, selector) {
      const direct = root.querySelector(selector); if(direct)return direct;
      for(const e of root.querySelectorAll('*'))if(e.shadowRoot){const r=find(e.shadowRoot,selector);if(r)return r;}
      return null;
    }
    """
    static func run(manager: IKCEFPage, browser: IKCEFPage, directory: URL) async throws {
        let toggle = "(() => { \(find) const t=find(document,'#enableToggle');if(!t)return false;t.click();return true;})()"
        guard try await value(manager, toggle, gesture: true) as? Bool == true else { throw CEFError.script("Native extension enable control was missing.") }
        try await wait(manager, "(() => { \(find) return find(document,'#enableToggle')?.checked === false; })()")
        browser.reloadIgnoringCache(false)
        try await loaded(browser)
        guard try await value(browser, "document.documentElement.dataset.ikagoExtensionFixture === undefined") as? Bool == true else {
            throw CEFError.script("A disabled extension still injected into a new document.")
        }
        _ = try await value(manager, toggle, gesture: true)
        try await wait(manager, "(() => { \(find) return find(document,'#enableToggle')?.checked === true; })()")
        browser.reloadIgnoringCache(false)
        try await wait(browser, "document.documentElement.dataset.ikagoExtensionFixture === 'active'")
        if !CommandLine.arguments.contains("--cef-smoke-read") {
            let manifestURL = directory.appending(path: "manifest.json")
            var manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as! [String: Any]
            manifest["version"] = "1.1"
            try JSONSerialization.data(withJSONObject: manifest).write(to: manifestURL, options: .atomic)
            guard try await value(manager, "(() => { \(find) const b=find(document,'#dev-reload-button');if(!b)return false;b.click();return true; })()", gesture: true) as? Bool == true else {
                throw CEFError.script("Native extension reload control was missing.")
            }
            try await wait(manager, "(() => { \(find) return find(document,'#version')?.textContent.trim() === '1.1'; })()")
            browser.reloadIgnoringCache(false)
        }
        try await wait(browser, "document.documentElement.dataset.ikagoExtensionVersion === '1.1' && document.documentElement.dataset.ikagoExtensionStorage === 'persisted'")
        print("CEF_EXTENSION_LIFECYCLE_OK disable enable reload-version storage-retained")
    }
    private static func value(_ page: IKCEFPage, _ expression: String, gesture: Bool = false) async throws -> Any? {
        let result = try await CEFSmoke.method(page, "Runtime.evaluate", ["expression": expression, "returnByValue": true, "userGesture": gesture])
        return (result["result"] as? [String: Any])?["value"]
    }
    private static func wait(_ page: IKCEFPage, _ expression: String) async throws {
        for _ in 0..<100 {
            if (try? await value(page, expression)) as? Bool == true { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw CEFError.script("Extension lifecycle fixture timed out: \(expression.prefix(200))")
    }
    private static func loaded(_ page: IKCEFPage) async throws {
        try await Task.sleep(for: .milliseconds(200))
        for _ in 0..<100 { if !page.loading { return }; try await Task.sleep(for: .milliseconds(50)) }
        throw CEFError.script("Extension lifecycle page did not reload.")
    }
}
