#if DEBUG
import AppKit
import WebKit

/// Reader, translation text handling, Save Page As, website notifications and web apps, on WebKit: what each hands the
/// page and the person, without the system parts (macOS notifications, the Translation models) that can't run headless.
@MainActor
enum PageToolChecks {
    static func run(_ browser: BrowserWindowController, base: String) async {
        guard WebProfiles.isTestMode, URL(string: base)?.host == "127.0.0.1" else { return }
        var failures = 0
        func check(_ value: Bool, _ title: String) {
            print("IKTEST pagetools \(value ? "PASS" : "FAIL") \(title)")
            if !value { failures += 1 }
        }
        let state = browser.state
        browser.open(base + "/?passwords-save", inNewTab: true)
        for _ in 0..<250 {
            if state.activeTab?.isLoading == false && state.activeTab?.url.hasSuffix("passwords-save") == true && browser.activeController?.page != nil { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        guard let page = browser.activeController?.page as? WebKitTab else { return check(false, "fixture loaded") }
        try? await Task.sleep(for: .milliseconds(300))

        // Reader: the article, without the page's furniture or anything that can run.
        let paragraph = "Ikago reads the web the way a person does, one careful paragraph at a time, and it keeps the long ones whole, commas included."
        _ = try? await page.evaluate("""
            document.body.innerHTML = `<nav><a href="/home">Home</a><a href="/about">About</a></nav>
            <div class="share-bar">Share this story</div>
            <article><h1>The Quiet Browser</h1><p class="byline">By Sam Writer</p>
            <p>\(paragraph) <a href="/more" onclick="window.__x=1">Read more</a> <script>window.__x=2</script></p>
            <p>\(paragraph)</p><p>\(paragraph)</p><p>\(paragraph)</p><p>\(paragraph)</p>
            <img src="/figure.png" alt="A figure" onerror="window.__x=3"><p>\(paragraph)</p></article>
            <aside>Related stories you may like</aside><footer>Copyright</footer>`; document.title = 'The Quiet Browser'; true
            """)
        let article = ReaderArticle(try? await page.evaluate(ReaderScript.extract))
        check(article?.title == "The Quiet Browser", "reader finds the headline")
        check(article?.html.contains("one careful paragraph") == true, "reader keeps the article text")
        check(article?.html.contains("Related stories") == false && article?.html.contains("Share this story") == false
              && article?.html.contains("Copyright") == false, "reader drops navigation, sharing, related and footer")
        check(article?.html.contains("<script") == false && article?.html.contains("onclick") == false
              && article?.html.contains("onerror") == false && article?.html.contains("__x") == false, "reader strips scripts and event handlers")
        check(article?.html.contains("href=\"\(base)/more\"") == true && article?.html.contains("src=\"\(base)/figure.png\"") == true,
              "reader makes links and images absolute")
        let doc = ReaderDocument.html(article, style: ReaderStyle(state.browserPreferences), dark: false)
        check(doc.contains("Content-Security-Policy") && doc.contains("<h1>The Quiet Browser</h1>"), "reader page has a policy and its headline")
        _ = try? await page.evaluate("document.body.innerHTML = '<p>Short.</p>'; true")
        check(ReaderArticle(try? await page.evaluate(ReaderScript.extract)) == nil, "a page without an article has no reader")

        // Translation: text nodes only, restorable.
        _ = try? await page.evaluate("""
            document.body.innerHTML = '<h1>Hola mundo</h1><p>Este es un navegador <code>let x = 1</code> muy rápido.</p><p translate="no">Marca</p><input value="texto">'; true
            """)
        let collected = try? await page.evaluate(TranslationScript.collect) as? [String: Any]
        let texts = collected?["texts"] as? [String] ?? []
        check(texts == ["Hola mundo", "Este es un navegador", "muy rápido."], "translation collects text, not code or translate=no")
        _ = try? await page.evaluate(TranslationScript.apply([(0, "Hello world"), (1, "This is a browser")])!)
        let changed = try? await page.evaluate("document.body.innerText") as? String
        check(changed?.contains("Hello world") == true && changed?.contains("This is a browser") == true && changed?.contains("<") == false,
              "translation writes text back")
        let markup = try? await page.evaluate("document.querySelector('code').textContent + '|' + document.querySelector('input').value") as? String
        check(markup == "let x = 1|texto", "translation leaves code and form values alone")
        _ = try? await page.evaluate(TranslationScript.restore)
        let restored = try? await page.evaluate("document.querySelector('h1').textContent") as? String
        check(restored == "Hola mundo", "show original restores the text")
        let spanish = PageTranslation.detect(["Este es un navegador muy rápido que lee la web con cuidado para ti."], declared: "")
        check(spanish.map { PageTranslation.same($0, Locale.Language(identifier: "es")) } == true
              && spanish.map { PageTranslation.same($0, Locale.Language(identifier: "en")) } == false, "the page's language is recognized")

        // Save Page As, on WebKit: a web archive and a PDF.
        let folder = FileManager.default.temporaryDirectory.appending(path: "IkagoPageTools-\(UUID())")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let archive = folder.appending(path: "page.webarchive"), pdf = folder.appending(path: "page.pdf")
        try? await page.savePage(as: .archive, to: archive)
        try? await page.savePage(as: .pdf, to: pdf)
        check((try? Data(contentsOf: archive))?.starts(with: Data("bplist".utf8)) == true, "a web archive is written")
        check((try? Data(contentsOf: pdf))?.starts(with: Data("%PDF".utf8)) == true, "a PDF is written")
        check(PageSaver.fileName("A/B: C\nD", "https://x.test") == "A B  C D" || PageSaver.fileName("A/B: C\nD", "https://x.test").contains("A"),
              "file names are made safe")

        // Notifications: the site's choice decides what the page is told and what is delivered.
        let host = "127.0.0.1"
        page.sendNotificationMessage(["t": "permission", "value": "default"])
        let beforeAsk = try? await page.webView.evaluateJavaScript("Notification.permission", in: nil, contentWorld: .page) as? String
        check(beforeAsk == "default", "a site that hasn't been asked reads default")
        state.setSitePermission(.allow, .notifications, host: host)
        _ = try? await page.webView.evaluateJavaScript("""
            window.__shown = 0; window.__n = new Notification('Build finished', {body: 'All green', tag: 'ci'});
            window.__n.onshow = () => { window.__shown += 1 }; true
            """, in: nil, contentWorld: .page)
        try? await Task.sleep(for: .milliseconds(400))
        check(WebNotifications.shared.testDelivered.contains { $0.hasPrefix("Build finished|\(host)|All green") },
              "an allowed site's notification is delivered under its name")
        let shown = try? await page.webView.evaluateJavaScript("window.__shown", in: nil, contentWorld: .page) as? Int
        check(shown == 1, "the page gets its show event")
        let delivered = WebNotifications.shared.testDelivered.count
        state.setSitePermission(.block, .notifications, host: host)
        _ = try? await page.webView.evaluateJavaScript("new Notification('Blocked one'); true", in: nil, contentWorld: .page)
        try? await Task.sleep(for: .milliseconds(300))
        check(WebNotifications.shared.testDelivered.count == delivered, "a blocked site's notification is dropped")
        state.setSitePermission(.ask, .notifications, host: host)
        check(state.sitePermission(.notifications, host: host) == .ask, "notification choices reset to ask")

        // Web apps: its own window, in-scope links stay, nothing saved to the session.
        let app = WebApp(name: "Pad", url: base + "/?webapp", spaceID: state.activeSpaceID)
        check(app.contains(base + "/other") && !app.contains("https://example.org/"), "a web app owns its own site")
        let icon = try? WebAppIcon.icns(for: app, favicon: nil)
        check(icon?.starts(with: Data("icns".utf8)) == true && (icon?.count ?? 0) > 1000, "the launcher icon is a valid icns")
        let launcher = try? WebAppLauncher.write(app, icon: nil, in: folder)
        let script = launcher.flatMap { try? String(contentsOf: $0.appending(path: "Contents/MacOS/launcher"), encoding: .utf8) }
        check(script?.contains("open \"ikago-app://\(app.id)\"") == true
              && launcher.map { FileManager.default.isExecutableFile(atPath: $0.appending(path: "Contents/MacOS/launcher").path) } == true,
              "the launcher opens the app through Ikago")
        state.browserPreferences.webApps = [app]
        check(WebApps.open(app.id), "a web app opens")
        try? await Task.sleep(for: .milliseconds(300))
        let window = BrowserWindows.all.first { $0.state.webApp?.id == app.id }
        check(window != nil && window?.state.sidebarVisible == false && window?.state.tabs.count == 1, "its window has one page and no sidebar")
        check(BrowserWindows.frontmost?.state.webApp == nil, "links from other apps never open inside a web app")
        check(browser.state.windowStates.contains { $0.webApp != nil }, "the window is tracked")
        window?.window?.close()
        try? await Task.sleep(for: .milliseconds(200))
        state.browserPreferences.webApps = nil
        print("IKTEST pagetoolchecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }

    /// Pictures for a look: the reader over an article, the translation card, the site card's page tools, a web app window.
    static func shots(_ c: BrowserWindowController, base: String, dir: String) async {
        guard WebProfiles.isTestMode, let window = c.window, let content = window.contentView else { return }
        c.open(base + "/?passwords-save", inNewTab: true)
        for _ in 0..<150 {
            if c.state.activeTab?.isLoading == false && c.activeController?.page != nil { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        let paragraph = "Ikago reads the web the way a person does, one careful paragraph at a time, and keeps the long ones whole, commas and all, so a long read stays easy on the eyes."
        _ = try? await c.activeController?.page?.evaluate("""
            document.body.innerHTML = `<nav><a href="/home">Home</a></nav><article><h1>The Quiet Browser</h1><p class="byline">By Sam Writer</p>
            <p>\(paragraph)</p><h2>Why it matters</h2><p>\(paragraph)</p><blockquote>\(paragraph)</blockquote><p>\(paragraph)</p><p>\(paragraph)</p></article>`;
            document.title = 'The Quiet Browser'; true
            """)
        try? await Task.sleep(for: .milliseconds(300))
        c.activeController?.toggleReader()
        try? await Task.sleep(for: .milliseconds(1200))
        print("IKTEST shot reader \(PeekShot.measure(content, window: window, save: dir + "/reader.png"))")
        c.activeController?.closeReader()
        c.chrome.siteInfoAnchor = CGPoint(x: 220, y: 80)
        c.chrome.showSiteInfo = true
        try? await Task.sleep(for: .milliseconds(900))
        print("IKTEST shot sitecard \(PeekShot.measure(content, window: window, save: dir + "/sitecard.png"))")
        let frame = window.frame
        window.setFrame(NSRect(x: frame.minX, y: frame.maxY - 520, width: frame.width, height: 520), display: true)
        try? await Task.sleep(for: .milliseconds(600))
        print("IKTEST shot sitecard-short \(PeekShot.measure(content, window: window, save: dir + "/sitecard-short.png"))")
        window.setFrame(frame, display: true)
        c.chrome.showSiteInfo = false
        c.chrome.translationJob = TranslationJob(source: Locale.Language(identifier: "es"), target: Locale.Language(identifier: "en"), texts: [], controller: nil)
        try? await Task.sleep(for: .milliseconds(900))
        print("IKTEST shot translation-choose \(PeekShot.measure(content, window: window, save: dir + "/translation-choose.png"))")
        c.chrome.translationJob = TranslationJob(source: Locale.Language(identifier: "es"), target: Locale.Language(identifier: "en"), texts: [], controller: nil, phase: .done)
        try? await Task.sleep(for: .milliseconds(700))
        print("IKTEST shot translation \(PeekShot.measure(content, window: window, save: dir + "/translation.png"))")
        c.chrome.translationJob = nil
        let app = WebApp(name: "Notes Pad", url: base + "/?webapp", spaceID: c.state.activeSpaceID)
        c.state.browserPreferences.webApps = [app]
        if WebApps.open(app.id), let web = BrowserWindows.all.first(where: { $0.state.webApp != nil }), let webWindow = web.window, let webContent = webWindow.contentView {
            try? await Task.sleep(for: .milliseconds(1200))
            print("IKTEST shot webapp \(PeekShot.measure(webContent, window: webWindow, save: dir + "/webapp.png"))")
            webWindow.close()
        }
        c.state.browserPreferences.webApps = nil
    }
}
#endif
