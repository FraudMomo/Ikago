#if DEBUG
import Foundation

@MainActor
enum DefaultBrowserChecks {
    static func run() async {
        var failures = 0
        func check(_ value: Bool, _ label: String) {
            print("IKTEST defaultbrowser \(value ? "PASS" : "FAIL") \(label)")
            if !value { failures += 1 }
        }
        let app = URL(fileURLWithPath: "/Applications/TestBrowser.app")
        let other = URL(fileURLWithPath: "/Applications/OtherBrowser.app")
        var handlers = ["http": other, "https": other, "html": other]
        var requested: [String] = []
        let setting = DefaultBrowserSetting(application: app, handler: { handlers[$0] }, candidates: { _ in [app, other] }, register: { _ in }, request: { url, scheme in
            requested.append(scheme); handlers[scheme] = url
        })
        check(!setting.isDefault && requested.isEmpty, "status lookup never changes defaults")
        await setting.makeDefault()
        check(setting.isDefault && requested == ["http", "https", "html"] && !setting.changing, "URL schemes and HTML requested and verified")
        await setting.makeDefault()
        check(requested.count == 3, "already-default schemes do not trigger requests")
        handlers["https"] = other; setting.refresh()
        check(!setting.isDefault, "mixed defaults are not reported as complete")
        await setting.makeDefault()
        check(requested == ["http", "https", "html", "https"] && setting.isDefault, "only missing scheme is requested")
        handlers = ["http": other, "https": other, "html": other]
        let cancelled = DefaultBrowserSetting(application: app, handler: { handlers[$0] }, candidates: { _ in [app, other] }, register: { _ in }, request: { _, _ in throw CocoaError(.userCancelled) })
        await cancelled.makeDefault()
        check(!cancelled.isDefault && !cancelled.changing && cancelled.message == "The request was cancelled.", "cancellation leaves status accurate and button retryable")
        let unchanged = DefaultBrowserSetting(application: app, handler: { handlers[$0] }, candidates: { _ in [app, other] }, register: { _ in }, request: { _, _ in })
        await unchanged.makeDefault()
        check(!unchanged.isDefault && unchanged.message != nil, "completion without changed handlers cannot claim success")
        let partial = DefaultBrowserSetting(application: app, handler: { handlers[$0] }, candidates: { _ in [app, other] }, register: { _ in }, request: { url, scheme in
            if scheme == "https" { throw CocoaError(.fileWriteNoPermission) }
            handlers[scheme] = url
        })
        await partial.makeDefault()
        check(!partial.isDefault && partial.message != nil && !partial.changing, "partial failure remains visible and retryable")
        var listed = false
        var registrations = 0
        handlers = ["http": app, "https": app, "html": app]
        let missing = DefaultBrowserSetting(application: app, handler: { handlers[$0] },
            candidates: { _ in listed ? [app] : [] }, register: { _ in registrations += 1; listed = true },
            request: { url, scheme in handlers[scheme] = url })
        check(!missing.isDefault && !missing.isRegistered, "stale preferred paths cannot hide missing browser registration")
        await missing.makeDefault()
        check(missing.isDefault && missing.isRegistered && registrations == 1, "Make Default repairs missing registration")
        listed = false; missing.refresh()
        check(!missing.isDefault, "status detects registration disappearing after a successful request")
        let broken = DefaultBrowserSetting(application: app, handler: { handlers[$0] }, candidates: { _ in [] },
            register: { _ in throw CocoaError(.fileReadNoPermission) }, request: { _, _ in check(false, "failed registration must not change defaults") })
        await broken.makeDefault()
        check(!broken.isDefault && !broken.changing && broken.message != nil, "registration failure stays visible and retryable")
        let documents = Bundle.main.object(forInfoDictionaryKey: "CFBundleDocumentTypes") as? [[String: Any]] ?? []
        check(documents.contains { ($0["LSItemContentTypes"] as? [String] ?? []).contains("public.html") && $0["CFBundleTypeRole"] as? String == "Viewer" },
              "app declares HTML viewer support for the macOS browser picker")
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
        let schemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        check(Set(["http", "https"]).isSubset(of: Set(schemes)), "app declares both browser URL schemes")
        print("IKTEST defaultbrowserchecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }
}
#endif
