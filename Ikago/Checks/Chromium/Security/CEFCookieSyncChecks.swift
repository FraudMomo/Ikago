import Foundation
import IKCEFBridge
import WebKit

/// Copies made-up cookies between a disposable Chromium profile and a nonpersistent WebKit store.
@MainActor
enum CEFCookieSyncChecks {
    private static let profile = "CookieSync"

    static func run() async throws {
        try CEFSessions.prepare(profile)
        let dataStore = WKWebsiteDataStore.nonPersistent()  // the cookie store doesn't keep this alive
        defer { withExtendedLifetime(dataStore) {} }
        let store = dataStore.httpCookieStore
        await store.setCookie(cookie("hostOnly", domain: "sync.example.test", httpOnly: true))
        await store.setCookie(cookie("shared", domain: ".example.test", secure: true, sameSite: .sameSiteLax))
        try await addToChromium(cookie("chromiumOnly", domain: "sync.example.test"))

        // A merge adds WebKit's cookies and removes nothing.
        let summary = try await EngineCookieSync.copyToChromium(from: store, profile: profile, mirror: false)
        var names = try await chromiumNames()
        try expect(names == ["chromiumOnly", "hostOnly", "shared"], "A merge should keep Chromium's cookies and add WebKit's. Got \(names), \(summary).")
        let copied = try await EngineCookieSync.chromiumCookies(profile)
        guard let hostOnly = copied.first(where: { $0["name"] as? String == "hostOnly" }),
              let shared = copied.first(where: { $0["name"] as? String == "shared" }) else { throw CEFError.noResult }
        try expect(hostOnly["httpOnly"] as? Bool == true && hostOnly["domain"] as? String == "sync.example.test", "HttpOnly or host-only identity was lost.")
        try expect(shared["secure"] as? Bool == true && shared["sameSite"] as? Int == 1 && shared["domain"] as? String == ".example.test", "Secure, SameSite or domain identity was lost.")
        try expect(shared["expires"] != nil, "An expiry was lost.")

        // A mirror carries a logout across: what WebKit doesn't have, Chromium loses.
        _ = try await EngineCookieSync.copyToChromium(from: store, profile: profile, mirror: true)
        names = try await chromiumNames()
        try expect(names == ["hostOnly", "shared"], "A mirror should remove cookies WebKit no longer has.")

        // And back the other way.
        try await addToChromium(cookie("fromChromium", domain: "sync.example.test", httpOnly: true))
        await store.setCookie(cookie("loggedOut", domain: "sync.example.test"))
        _ = try await EngineCookieSync.copyToWebKit(profile: profile, store: store, mirror: true)
        let result = await store.allCookies()
        try expect(Set(result.map(\.name)) == ["fromChromium", "hostOnly", "shared"], "WebKit should match Chromium after a mirror.")
        try expect(result.first { $0.name == "fromChromium" }?.isHTTPOnly == true, "HttpOnly didn't reach WebKit.")
        try expect(result.first { $0.name == "shared" }?.sameSitePolicy == .sameSiteLax, "SameSite didn't reach WebKit.")
        print("CEF_COOKIE_SYNC_OK merge mirror both-directions httponly samesite")
    }

    private static func cookie(_ name: String, domain: String, secure: Bool = false, httpOnly: Bool = false, sameSite: HTTPCookieStringPolicy? = nil) -> HTTPCookie {
        var properties: [HTTPCookiePropertyKey: Any] = [.name: name, .value: "fixture", .domain: domain, .path: "/", .expires: Date().addingTimeInterval(3600)]
        if secure { properties[.secure] = "TRUE" }
        if httpOnly { properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
        if let sameSite { properties[.sameSitePolicy] = sameSite.rawValue }
        return HTTPCookie(properties: properties)!
    }

    private static func addToChromium(_ cookie: HTTPCookie) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            IKCEFContexts.setCookie(cookie, sameSite: 1, profile: profile) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }

    private static func chromiumNames() async throws -> [String] {
        try await EngineCookieSync.chromiumCookies(profile).compactMap { $0["name"] as? String }.sorted()
    }

    private static func expect(_ condition: Bool, _ message: String) throws {
        guard condition else { throw CEFError.script(message) }
    }
}
