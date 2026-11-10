import AppKit
import IKCEFBridge

/// Developer aid: `--cef-smoke-dump <url>` loads a page on the disposable smoke profile, in a window
/// that is never shown, and prints what its video players look like to Chromium. Logged out, no data kept.
@MainActor
enum CEFPageDump {
    static func run(url: String) async -> Int32 {
        setvbuf(stdout, nil, _IOLBF, 0)
        do {
            try CEFSessions.prepare("Dump")
            let translate = CommandLine.arguments.contains("--cef-smoke-translate")
            if translate { MediaTranslation.apply(true) }
            let page = try IKCEFPage.make(profile: "Dump")
            if translate { page.documentStartScript = MediaTranslation.documentStartScript }
            defer { page.close() }
            let host = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 900), styleMask: [.borderless], backing: .buffered, defer: false)
            host.contentView = page
            for _ in 0..<200 where !page.ready { try await Task.sleep(for: .milliseconds(50)) }
            // `--cef-smoke-extension <folder>`: load an unpacked extension first, then open its new-tab page
            // through a normal Ikago tab, the way ⌘T does.
            if let index = CommandLine.arguments.firstIndex(of: "--cef-smoke-extension"), CommandLine.arguments.indices.contains(index + 1) {
                let folder = URL(fileURLWithPath: CommandLine.arguments[index + 1])
                let manager = ChromiumExtensions()
                defer { manager.shutDown() }
                print("CEF_DUMP_STAGE installing")
                await manager.install(folder: folder, profile: "Dump")
                print("CEF_DUMP_EXTENSIONS issue=\(manager.issue ?? "none") items=\(manager.items.map { "\($0.name) \($0.id) enabled=\($0.enabled) newtab=\($0.newTabPage ?? "-")" })")
                guard let item = manager.items.first(where: { $0.newTabPage != nil }), let pagePath = item.newTabPage else {
                    // No new-tab page: check content blocking instead. A normal site loads; an ad server shouldn't.
                    let tab = try CEFWebTab(profileID: "Dump")
                    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 900), styleMask: [.borderless], backing: .buffered, defer: false)
                    window.contentView = tab.page
                    for _ in 0..<200 where !tab.page.ready { try await Task.sleep(for: .milliseconds(50)) }
                    try await Task.sleep(for: .seconds(6))  // the extension registers its rules after installing
                    tab.load(url)
                    try await Task.sleep(for: .seconds(6))
                    let probe = try? await tab.callAsync("""
                    const p = u => fetch(u, {mode: 'no-cors', cache: 'no-store'}).then(() => 'loaded', () => 'blocked')
                    return 'site=' + await p('https://example.com/?x=' + Date.now()) + ' ad=' + await p('https://c.amazon-adsystem.com/aax2/apstag.js?x=' + Date.now())
                    """)
                    print("CEF_DUMP_BLOCKING \(probe.map { "\($0)" } ?? "probe failed")")
                    // The extension's popup, without and with the layer that lets it see this tab.
                    if let item = manager.items.first, let popupPath = item.popup {
                        let title = (try? await tab.evaluate("document.title")) as? String ?? ""
                        for withLayer in [false, true] {
                            let popup = try IKCEFPage.make(profile: "Dump")
                            if withLayer { popup.documentStartScript = ChromiumPopupLayer.source(url: tab.currentURL, title: title) }
                            let holder = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 480), styleMask: [.borderless], backing: .buffered, defer: false)
                            holder.contentView = popup
                            for _ in 0..<200 where !popup.ready { try await Task.sleep(for: .milliseconds(25)) }
                            popup.loadURL("chrome-extension://\(item.id)/\(popupPath)")
                            try await Task.sleep(for: .seconds(5))
                            let text = try? await HiddenChromiumPage.call(popup, "Runtime.evaluate", ["expression": "(async () => JSON.stringify({layer: !!globalThis.__ikagoPopupLayer, query: (await chrome.tabs.query({active: true, currentWindow: true})).map(t => [t.id, t.url]), text: document.body.innerText.replace(/\\s+/g, ' ').slice(0, 120)}))()", "awaitPromise": true, "returnByValue": true])
                            print("CEF_DUMP_POPUP layer=\(withLayer) \((text?["result"] as? [String: Any])?["value"] ?? "nil")")
                            popup.close()
                        }
                    }
                    tab.tearDown()
                    try? await Task.sleep(for: .seconds(1))
                    return 0
                }
                let tab = try CEFWebTab(profileID: "Dump")
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 900), styleMask: [.borderless], backing: .buffered, defer: false)
                window.contentView = tab.page
                for _ in 0..<200 where !tab.page.ready { try await Task.sleep(for: .milliseconds(50)) }
                print("CEF_DUMP_STAGE opening")
                tab.load("chrome-extension://\(item.id)/\(pagePath)")
                try await Task.sleep(for: .seconds(8))
                let seen = try? await tab.evaluate("JSON.stringify({url: location.href, title: document.title, text: (document.body && document.body.innerText || '').slice(0, 200), nodes: document.querySelectorAll('*').length})")
                print("CEF_DUMP_NEWTAB currentURL=\(tab.currentURL) page=\(seen.map { "\($0)" } ?? "evaluate failed")")
                tab.tearDown()
                try? await Task.sleep(for: .seconds(1))
                return 0
            }
            page.loadURL(url)
            try await Task.sleep(for: .seconds(10))
            let tab = try CEFWebTab(profileID: "Dump", adopting: page)
            let result = try await tab.evaluate("""
            (() => {
              const brief = el => el ? el.outerHTML.replace(/\\s+/g, ' ').slice(0, 1400) : null
              const out = {url: location.href, videos: [], testids: [], error: null}
              for (const v of document.querySelectorAll('video')) { const r = v.getBoundingClientRect(); const hit = document.elementFromPoint(r.left + r.width/2, r.top + r.height/2); let chain = [], a = v; for (let i = 0; i < 8 && a; i++, a = a.parentElement) { const q = a.getBoundingClientRect(); chain.push(a.tagName + ' ' + Math.round(q.width) + 'x' + Math.round(q.height) + (a.contains(hit) ? ' HAS-HIT' : '')) } out.videos.push({hit: hit && (hit.tagName + ' ' + (hit.className||'').toString().slice(0,40) + ' ' + (hit.textContent||'').slice(0,40)), chain, poster: v.poster, src: v.currentSrc || v.src, err: v.error && v.error.code, ns: v.networkState, rect: JSON.stringify(v.getBoundingClientRect())}) }
              const ids = new Set(); document.querySelectorAll('[data-testid]').forEach(e => ids.add(e.dataset.testid)); out.testids = [...ids].filter(t => /video|media|player|tweetPhoto|card/i.test(t))
              const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT)
              while (walker.nextNode()) if (/could not be played/i.test(walker.currentNode.textContent)) {
                let box = walker.currentNode.parentElement
                for (let i = 0; i < 9 && box.parentElement; i++) box = box.parentElement
                out.error = brief(box); break
              }
              const player = document.querySelector('[data-testid="videoPlayer"], [data-testid="videoComponent"]')
              out.player = brief(player)
              const article = document.querySelector('article')
              out.articleLinks = article ? [...article.querySelectorAll('a[href*="/status/"]')].map(a => a.getAttribute('href') + (a.querySelector('time') ? ' [time]' : '')).slice(0, 8) : []
              out.images = article ? [...article.querySelectorAll('img')].map(i => i.src).filter(s => /twimg/.test(s)).slice(0, 8) : []
              return JSON.stringify(out, null, 1)
            })()
            """)
            print("CEF_DUMP \(result ?? "nil")")
            if translate {
                // X's own player, fed through the translation layer: is it really playing?
                let playback = try await tab.evaluate("""
                (async () => JSON.stringify({videos: [...document.querySelectorAll('video')].map(v => ({
                  time: v.currentTime, paused: v.paused, ready: v.readyState, error: v.error && v.error.code,
                  buffered: [...Array(v.buffered.length).keys()].map(i => [v.buffered.start(i), v.buffered.end(i)]),
                  size: [v.videoWidth, v.videoHeight], src: (v.currentSrc || '').slice(0, 30),
                  frames: v.getVideoPlaybackQuality ? [v.getVideoPlaybackQuality().totalVideoFrames, v.getVideoPlaybackQuality().droppedVideoFrames] : null
                })),
                // powerEfficient: Chromium decodes the translated AV1 in hardware.
                av1: await navigator.mediaCapabilities.decodingInfo({type: 'media-source', video: {contentType: 'video/mp4; codecs="av01.0.13M.08"',
                  width: 1280, height: 720, bitrate: 4000000, framerate: 30}}).then(r => ({supported: r.supported, smooth: r.smooth, powerEfficient: r.powerEfficient}))
                }))()
                """)
                print("CEF_DUMP_PLAYBACK \(playback ?? "nil")")
            }
            // The native player's view of the page: what the script reports and the stream it resolves to.
            let scan = try await tab.evaluate(NativeVideoScript.source + "\n;JSON.stringify(window.__ikagoMedia.scan())")
            print("CEF_DUMP_SCAN \(scan ?? "nil")")
            if let text = scan as? String, let data = text.data(using: .utf8),
               let list = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                for report in list.compactMap(NativeVideoReport.init) {
                    let stream = await NativeVideoSource.stream(for: report.request)
                    print("CEF_DUMP_STREAM key=\(report.key) shown=\(report.shown) covered=\(report.covered) hiddenTop=\(report.hiddenTop) -> \(stream?.url.absoluteString ?? "none") gif=\(stream?.isGIF ?? false)")
                }
            }
            tab.tearDown()
            try? await Task.sleep(for: .seconds(1))  // let Chromium finish closing before shutdown
            return 0
        } catch {
            print("CEF_DUMP_FAILED \(error.localizedDescription)")
            return 1
        }
    }
}
