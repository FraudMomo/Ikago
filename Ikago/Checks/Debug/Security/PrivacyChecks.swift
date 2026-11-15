#if DEBUG
import AppKit
import WebKit

/// Private windows, clearing data, and the address-bar padlock.
@MainActor
enum PrivacyChecks {
    static func run(_ browser: BrowserWindowController, base: String) async {
        guard WebProfiles.isTestMode else { return }
        var failures = 0
        func check(_ value: Bool, _ message: String) {
            print("IKTEST privacy \(value ? "PASS" : "FAIL") \(message)")
            if !value { failures += 1 }
        }
        let main = browser.state

        // Padlock states.
        let plain = TabItem(url: "http://example.com/"), mixed = TabItem(url: "https://example.com/")
        mixed.hasOnlySecureContent = false
        check(PageSecurity(plain) == .insecure && PageSecurity(mixed) == .mixed
              && PageSecurity(TabItem(url: "https://example.com/")) == .secure
              && PageSecurity(TabItem(url: "ikago://settings")) == .none, "padlock: secure, mixed, insecure and internal pages")

        // Private window.
        (NSApp.delegate as? AppDelegate)?.openPrivateWindow()
        try? await Task.sleep(for: .milliseconds(500))
        let window = NSApp.windows.compactMap { $0.windowController as? BrowserWindowController }.first { $0.state.isPrivate }
        check(window != nil, "a private window opens")
        if let window {
            let probe = base + "/?private-probe"
            window.open(probe, inNewTab: true)
            try? await Task.sleep(for: .milliseconds(1200))
            let page = window.activeController?.page
            check(page?.webView.configuration.websiteDataStore.isPersistent == false, "private pages use in-memory website data")
            check(page?.webView.configuration.webExtensionController == nil, "extensions don't run in private windows")
            check(window.state.history.isEmpty && !main.history.contains { $0.url == probe }, "private visits stay out of history")
            _ = try? await page?.callAsync("document.cookie = 'ikagoPrivate=1; path=/'; return document.cookie")
            let mainCookies = await WebProfiles.dataStore(for: main.activeSpace.profileID).httpCookieStore.allCookies()
            check(!mainCookies.contains { $0.name == "ikagoPrivate" }, "private cookies don't reach normal Spaces")
            main.saveNow()
            let saved = String(decoding: main.store.decrypted("session.json") ?? Data(), as: UTF8.self)
            check(!saved.contains("private-probe"), "private tabs are never written to the session")
            window.window?.close()
            try? await Task.sleep(for: .milliseconds(300))
            check(!NSApp.windows.contains { ($0.windowController as? BrowserWindowController)?.state.isPrivate == true && $0.isVisible },
                  "closing the private window ends it")
        }

        // Private traces.
        let privateStore = WebProfiles.dataStore(for: "Private-check")
        check(WebProfiles.isPrivateStore(privateStore) && !WebProfiles.isPrivateStore(WebProfiles.dataStore(for: main.activeSpace.profileID)),
              "private window stores are recognized")
        WebProfiles.forget("Private-check")
        let historyFiles = ["downloads.json", "downloads.backup.json"].map { DownloadHistoryStore.standard.directory.appending(path: $0) }
        func inDownloadHistory(_ text: String) -> Bool {
            historyFiles.contains { String(decoding: DownloadHistoryStore.standard.decrypted($0.lastPathComponent) ?? Data(), as: UTF8.self).contains(text) }
        }
        DownloadCenter.shared.save(Data("x".utf8), suggestedFilename: "private-probe.txt", sourceURL: URL(string: base + "/private-download-probe"), isPrivate: true)
        DownloadCenter.shared.saveNow()
        check(!inDownloadHistory("private-download-probe"), "private downloads stay out of the saved history")
        if let icon = URL(string: base + "/icon.svg?private-favicon") {
            let image = await FaviconCache.shared.image(pageURL: base + "/?private-favicon", iconURL: icon, persist: false)
            check(image != nil, "private windows still show favicons")
            check(!FileManager.default.fileExists(atPath: FaviconCache.shared.file(for: icon.absoluteString).path)
                  && !FileManager.default.fileExists(atPath: FaviconCache.shared.file(for: "page:" + base + "/?private-favicon").path),
                  "private favicons never reach the disk")
        }

        // What reaches the system's parsers, and what can open as a page.
        check(FaviconCache.isFaviconFormat(Data([0x89, 0x50, 0x4E, 0x47, 0x0D])) && FaviconCache.isFaviconFormat(Data("  <svg xmlns='x'/>".utf8))
              && FaviconCache.isFaviconFormat(Data([0x00, 0x00, 0x01, 0x00, 0x01])), "favicon formats sites use are accepted")
        check(!FaviconCache.isFaviconFormat(Data("%PDF-1.7".utf8)) && !FaviconCache.isFaviconFormat(Data([0x49, 0x49, 0x2A, 0x00]))
              && !FaviconCache.isFaviconFormat(Data("<html>".utf8)), "PDF, TIFF and HTML never decode as favicons")
        check(WebKitTab.isBlockedDataDocument(URL(string: "data:text/html,x")!) && WebKitTab.isBlockedDataDocument(URL(string: "data:image/svg+xml,x")!)
              && !WebKitTab.isBlockedDataDocument(URL(string: "data:image/png;base64,AA")!), "scriptable data: documents can't open as pages")
        check(OmniboxURL.display("https://accounts.google.com:pw@evil.example/login") == "evil.example/login", "suggestions show the real host, not user:password@")

        await SafetyChecks.run(browser, check: check)

        // Clear browsing data (what "clear when quitting" runs).
        main.history.append(Visit(url: base + "/?clear-probe", title: "probe", time: 1))
        main.saveNow(); main.saveNow()  // on disk in both the session and its backup
        check(String(decoding: main.store.decrypted("session.backup.json") ?? Data(), as: UTF8.self).contains("clear-probe"), "the probe is in the backup before clearing")
        for name in ["session.json", "session.backup.json"] {
            let raw = (try? Data(contentsOf: main.store.directory.appending(path: name))) ?? Data()
            check(SealedStorage.isSealed(raw) && !String(decoding: raw, as: UTF8.self).contains("clear-probe"), "\(name) is encrypted on disk")
        }
        DownloadCenter.shared.save(Data("x".utf8), suggestedFilename: "clear-probe.txt", sourceURL: URL(string: base + "/clear-download-probe"))
        DownloadCenter.shared.saveNow()
        await main.clearBrowsingData()
        check(main.history.isEmpty && main.closed.isEmpty, "clearing removes history and recently closed tabs")
        check(!["session.json", "session.backup.json"].contains { String(decoding: main.store.decrypted($0) ?? Data(), as: UTF8.self).contains("clear-probe") }, "clearing also removes history from the session backup")
        await SealedChecks.run(check: check)
        ProtectedStorageChecks.run(check: check)
        CRXVerifierChecks.run(check: check)
        await PasswordVaultChecks.run(check: check)
        ExtensionSyncChecks.run(check: check)
        check(!inDownloadHistory("clear-download-probe"), "clearing removes download history, including its backup")

        print("IKTEST privacychecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }
}
#endif
