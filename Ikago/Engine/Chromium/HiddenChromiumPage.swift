import AppKit
import IKCEFBridge

/// A Chromium service page that is never shown (chrome://extensions, for example), driven through
/// the in-process DevTools protocol. There is no debugging port.
@MainActor
struct HiddenChromiumPage {
    let id: Int
    let page: IKCEFPage

    /// Opens a page with `opener` and waits until it has loaded.
    static func open(_ opener: () throws -> NSNumber) async throws -> HiddenChromiumPage {
        let before = Set(IKCEFNativeTools.windows().compactMap { $0["id"] as? Int })
        _ = try opener()
        for _ in 0..<300 {
            for item in IKCEFNativeTools.windows() {
                guard let id = item["id"] as? Int, !before.contains(id), item["loading"] as? Bool == false,
                      (item["url"] as? String)?.isEmpty == false, let page = IKCEFNativeTools.hiddenPage(forWindow: id) else { continue }
                return HiddenChromiumPage(id: id, page: page)
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw CEFError.script("A Chromium service did not start.")
    }

    func close() { IKCEFNativeTools.closeBrowser(id) }

    /// Evaluates async JavaScript in the page and returns its value as JSON text.
    @discardableResult
    func run(_ expression: String) async throws -> String? {
        let wrapped = "(async () => JSON.stringify(await (\(expression))))()"
        let result = try await Self.call(page, "Runtime.evaluate", ["expression": wrapped, "returnByValue": true,
                                                                   "awaitPromise": true, "userGesture": true])
        if let details = result["exceptionDetails"] as? [String: Any] {
            let exception = details["exception"] as? [String: Any]
            throw CEFError.script(exception?["description"] as? String ?? details["text"] as? String ?? "Chromium rejected the request.")
        }
        return (result["result"] as? [String: Any])?["value"] as? String
    }

    static func call(_ page: IKCEFPage, _ name: String, _ parameters: [String: Any]) async throws -> [String: Any] {
        let data: Data = try await withCheckedThrowingContinuation { continuation in
            page.devToolsMethod(name, parameters: parameters) { result, error in
                if let error { continuation.resume(throwing: error) }
                else if let result {
                    do { continuation.resume(returning: try JSONSerialization.data(withJSONObject: result)) }
                    catch { continuation.resume(throwing: error) }
                } else { continuation.resume(throwing: CEFError.noResult) }
            }
        }
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }
}

/// Clears a Space's website data over the DevTools protocol, on an embedded page that is never shown.
/// Extensions stay installed, because they aren't among the origins cleared.
@MainActor
enum ChromiumWebsiteData {
    /// Chromium has no API listing every origin holding storage, so this clears those with cookies, `knownURLs`
    /// (the sites in history and open tabs) and any the profile's files name (`storedOrigins`).
    /// Cookies and the cache are cleared for all sites.
    static func clear(profile: String, knownURLs: [String] = []) async throws {
        try CEFSessions.prepare(profile)
        let page = try IKCEFPage.make(profile: profile)
        defer { page.close() }
        let host = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        host.isReleasedWhenClosed = false
        host.contentView = page
        defer { withExtendedLifetime(host) {} }
        for _ in 0..<200 where !page.ready { try await Task.sleep(for: .milliseconds(25)) }
        guard page.ready else { throw CEFError.script("Chromium could not start to clear website data.") }

        let cookies = try await settled(page, "Network.getAllCookies", [:])["cookies"] as? [[String: Any]] ?? []
        var origins = Set(knownURLs.compactMap(origin(of:))).union(storedOrigins(in: CEFSessions.directory(for: profile)))
        for cookie in cookies {
            guard let domain = cookie["domain"] as? String else { continue }
            let host = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
            origins.formUnion(["https://\(host)", "http://\(host)"])
        }
        for origin in origins.sorted() {
            _ = try await settled(page, "Storage.clearDataForOrigin", ["origin": origin, "storageTypes": "all"])
        }
        _ = try await settled(page, "Network.clearBrowserCookies", [:])
        _ = try await settled(page, "Network.clearBrowserCache", [:])
    }

    /// A new page's first navigation can commit mid-command, which cancels it. These commands are safe to
    /// repeat, and a clear that quietly gave up would leave data the person asked to remove.
    private static func settled(_ page: IKCEFPage, _ name: String, _ parameters: [String: Any]) async throws -> [String: Any] {
        for _ in 0..<9 {
            if let result = try? await HiddenChromiumPage.call(page, name, parameters) { return result }
            try await Task.sleep(for: .milliseconds(150))
        }
        return try await HiddenChromiumPage.call(page, name, parameters)
    }

    /// Best effort, from Chromium's private on-disk layout: the quota database and Local Storage name their
    /// origins in plain bytes, and IndexedDB folders are named after theirs. A stray URL in stored data only
    /// adds a harmless extra clear. Writes still in Chromium's memory, or compressed on disk, can be missed.
    static func storedOrigins(in profile: URL) -> Set<String> {
        let manager = FileManager.default
        var origins = Set<String>()
        var files = [profile.appending(path: "WebStorage/QuotaManager")]
        let localStorage = profile.appending(path: "Local Storage/leveldb")
        files += ((try? manager.contentsOfDirectory(at: localStorage, includingPropertiesForKeys: nil)) ?? [])
            .filter { ["log", "ldb"].contains($0.pathExtension) }
        let pattern = /https?:\/\/[a-zA-Z0-9.\-]+(?::[0-9]{1,5})?/
        for file in files {
            guard let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { continue }
            let text = String(decoding: data, as: Unicode.ASCII.self)
            for match in text.matches(of: pattern) where origins.count < maxScannedOrigins { origins.insert(String(match.output).lowercased()) }
        }
        let indexedDB = (try? manager.contentsOfDirectory(atPath: profile.appending(path: "IndexedDB").path)) ?? []
        for folder in indexedDB {
            // https_example.com_0.indexeddb.leveldb (the last number is the port, 0 meaning the default).
            let parts = folder.split(separator: ".indexeddb").first?.split(separator: "_") ?? []
            guard parts.count == 3, ["http", "https"].contains(String(parts[0])) else { continue }
            origins.insert("\(parts[0])://\(parts[1])" + (parts[2] == "0" ? "" : ":\(parts[2])"))
        }
        return origins
    }
    private static let maxScannedOrigins = 5000

    private static func origin(of url: String) -> String? {
        guard let components = URLComponents(string: url), let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme), let host = components.host else { return nil }
        return "\(scheme)://\(host)" + (components.port.map { ":\($0)" } ?? "")
    }
}
