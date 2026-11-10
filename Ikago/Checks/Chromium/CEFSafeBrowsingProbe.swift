import AppKit
import IKCEFBridge

/// Optional network diagnostic against Google's benign phishing fixture. No bypasses,
/// synthetic threat lists, keys, downloads or changes to the user's profile.
@MainActor
enum CEFSafeBrowsingProbe {
    static func run(profile: String) async throws {
        guard CommandLine.arguments.contains("--cef-smoke-safe-browsing") else { return }
        _ = try IKCEFNativeTools.openSecurity(forProfile: profile)
        var page: IKCEFPage?
        for _ in 0..<100 {
            if let item = IKCEFNativeTools.windows().first(where: { ($0["url"] as? String)?.hasPrefix("chrome://settings/security") == true && $0["loading"] as? Bool == false }),
               let id = item["id"] as? Int { page = IKCEFNativeTools.hiddenPage(forWindow: id); if page != nil { break } }
            try await Task.sleep(for: .milliseconds(100))
        }
        guard let page else { throw CEFError.script("Safe Browsing diagnostic window did not become ready.") }
        defer { IKCEFNativeTools.closeAll() }
        var database = try await databaseStatus(page)
        // A fresh profile schedules its first list update later. A loaded test
        // page before that update is not evidence that verdicts are unavailable.
        for tick in 0..<40 {
            if (database["bytes"] as? Int ?? 0) > 0 { break }
            if let code = database["networkStatus"] as? Int, code >= 400 || code < 0 {
                print("CEF_SAFE_BROWSING_UPDATE_FAILED status=\(code)"); break
            }
            if tick % 6 == 0 { print("CEF_SAFE_BROWSING_WARMUP elapsed=\(tick * 5)s") }
            try await Task.sleep(for: .seconds(5))
            database = try await databaseStatus(page, navigate: false)
        }
        var interstitial = false
        var safeBrowsingWarning = false
        page.eventHandler = { name, _ in if name == "interstitial" { interstitial = true } }
        _ = try await CEFSmoke.method(page, "Page.enable", [:])
        let navigation = try await CEFSmoke.method(page, "Page.navigate", ["url": "https://testsafebrowsing.appspot.com/s/phishing.html"])
        var details: [String: Any] = [:]
        for _ in 0..<100 {
            let result = try? await CEFSmoke.method(page, "Runtime.evaluate", ["expression": """
                ({title:document.title,url:location.href,ready:document.readyState,
                  bodyLength:document.body?.innerText.length || 0,
                  warningType:window.loadTimeDataRaw?.type || window.loadTimeData?.getString?.('type') || null,
                  nativeController:typeof window.securityInterstitialController !== 'undefined'})
                """, "returnByValue": true])
            details = (result?["result"] as? [String: Any])?["value"] as? [String: Any] ?? [:]
            if details["warningType"] as? String == "SAFEBROWSING", details["nativeController"] as? Bool == true {
                safeBrowsingWarning = true; break
            }
            if details["ready"] as? String == "complete", (details["bodyLength"] as? Int ?? 0) > 0 { break }
            try await Task.sleep(for: .milliseconds(200))
        }
        print("CEF_SAFE_BROWSING_LIVE_PROBE interstitialEvent=\(interstitial) navigationError=\(navigation["errorText"] ?? "none") document=\(details)")
        // A TLS/network interstitial event must never count as a threat verdict.
        print(safeBrowsingWarning ? "CEF_SAFE_BROWSING_INTERSTITIAL_OBSERVED" : "CEF_SAFE_BROWSING_LIVE_VERDICTS_UNVERIFIED")
        _ = try await databaseStatus(page)
    }
    private static func databaseStatus(_ page: IKCEFPage, navigate: Bool = true) async throws -> [String: Any] {
        if navigate { _ = try await CEFSmoke.method(page, "Page.navigate", ["url": "chrome://safe-browsing/"]) }
        for _ in 0..<80 {
            let check = try? await CEFSmoke.method(page, "Runtime.evaluate", ["expression": "location.protocol === 'chrome:' && location.host === 'safe-browsing' && document.readyState === 'complete'", "returnByValue": true])
            if (check?["result"] as? [String: Any])?["value"] as? Bool == true { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let result = try? await CEFSmoke.method(page, "Runtime.evaluate", ["expression": """
            (async () => {
              if(location.protocol !== 'chrome:' || location.host !== 'safe-browsing')return {available:false};
              const {sendWithPromise} = await import('chrome://resources/js/cr.js');
              const info = await Promise.race([sendWithPromise('getDatabaseManagerInfo'),new Promise(r=>setTimeout(()=>r(null),3000))]);
              const result = {available:Array.isArray(info),entries:Array.isArray(info)?info.length:0,status:[],bytes:0};
              // This endpoint returns alternating labels/values. Only emit known
              // update status fields, never cookies, API keys or full-hash data.
              if(Array.isArray(info))for(let i=0;i+1<info.length;i+=2)
                if(typeof info[i]==='string' && /update|database size|failure|network status/i.test(info[i])) {
                  result.status.push([info[i],String(info[i+1]).replace(/https?:[^\\s]+/g,'[URL omitted]').slice(0,120)]);
                  if(/^Database size/i.test(info[i]))result.bytes=Number(String(info[i+1]).replace(/,/g,'')) || 0;
                  if(/^Last update network status code$/i.test(info[i]))result.networkStatus=Number(info[i+1]);
                }
              return result;
            })()
            """, "returnByValue": true, "awaitPromise": true])
        let status = (result?["result"] as? [String: Any])?["value"] as? [String: Any] ?? [:]
        if navigate { print("CEF_SAFE_BROWSING_DATABASE \(status)") }
        return status
    }
}
