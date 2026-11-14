#if DEBUG
import Foundation

/// Sound the plain media scan used to miss: a player inside a shadow root, and Web Audio (WebKit's own flag).
@MainActor
enum MediaDetectionChecks {
    static func run(_ browser: BrowserWindowController) async {
        var failures = 0
        func check(_ value: Bool, _ label: String) {
            print("IKTEST mediadetection \(value ? "PASS" : "FAIL") \(label)")
            if !value { failures += 1 }
        }
        func wait(until done: () -> Bool) async {
            for _ in 0..<40 where !done() { try? await Task.sleep(for: .milliseconds(100)) }
        }
        let audio = MediaFullscreenChecks.wave().base64EncodedString()
        let pages: [(name: String, html: String, play: String)] = [
            ("shadow root player", """
             <!doctype html><title>Shadow</title><x-player></x-player><script>
             customElements.define('x-player', class extends HTMLElement { constructor() { super();
               this.attachShadow({mode:'open'}).innerHTML='<audio loop src="data:audio/wav;base64,\(audio)"></audio>'; } });
             </script>
             """, "const a=document.querySelector('x-player').shadowRoot.querySelector('audio');a.volume=0.01;await a.play();return true;"),
            ("Web Audio", "<!doctype html><title>Web Audio</title><p>tone</p>", """
             const c=new AudioContext(), o=c.createOscillator(), g=c.createGain(); g.gain.value=0.001;
             o.connect(g).connect(c.destination); o.start(); await c.resume(); window.__tone=c; return true;
             """)
        ]
        for (index, fixture) in pages.enumerated() {
            let file = SessionStore.testDirectory.appending(path: "media-detection-\(index).html")
            do { try fixture.html.write(to: file, atomically: true, encoding: .utf8) } catch { check(false, "write \(fixture.name)"); continue }
            browser.open(file.absoluteString, inNewTab: true)
            try? await Task.sleep(for: .milliseconds(700))
            guard let controller = browser.activeController, let page = controller.page else { check(false, "\(fixture.name) starts"); continue }
            let tab = controller.tab
            check(!tab.isPlayingAudio, "\(fixture.name) silent before playing")
            do { _ = try await page.callAsync(fixture.play) } catch { check(false, "\(fixture.name) plays: \(error)"); continue }
            await wait { tab.isPlayingAudio }
            check(tab.isPlayingAudio, "\(fixture.name) shows the tab as playing")
            if index == 0 {
                // The script's own report (Chromium relies on it): the shadow-root player is found and controllable.
                await wait { tab.playback.available && tab.playback.playing }
                check(tab.playback.available && tab.playback.playing, "script finds the shadow-root player")
            }
            browser.closeTab(tab.id)
        }
        // Sound that stops after the page changed its address in place (pushState, as YouTube does) turns the
        // speaker off: the report that said "playing" belonged to the same document, not the old address.
        let file = SessionStore.testDirectory.appending(path: "media-detection-stop.html")
        try? "<!doctype html><title>Stop</title><audio loop src=\"data:audio/wav;base64,\(audio)\"></audio>".write(to: file, atomically: true, encoding: .utf8)
        browser.open(file.absoluteString, inNewTab: true)
        try? await Task.sleep(for: .milliseconds(700))
        if let controller = browser.activeController, let page = controller.page {
            let tab = controller.tab
            _ = try? await page.callAsync("const a=document.querySelector('audio');a.volume=0.01;await a.play();return true;")
            await wait { tab.isPlayingAudio }
            _ = try? await page.callAsync("history.pushState({}, '', '?moved'); return true;")
            try? await Task.sleep(for: .milliseconds(400))
            _ = try? await page.callAsync("document.querySelector('audio').pause(); return true;")
            await wait { !tab.isPlayingAudio }
            check(!tab.isPlayingAudio, "the speaker turns off when sound stops after an in-page address change")
            browser.closeTab(tab.id)
        } else { check(false, "stop fixture starts") }
        print("IKTEST mediadetectionchecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }
}
#endif
