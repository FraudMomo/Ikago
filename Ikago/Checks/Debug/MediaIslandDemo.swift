#if DEBUG
import AppKit
import Foundation

/// Opens a quiet looping track with Media Session metadata, so the sidebar's media island can be looked at.
/// `mediademo`, then `snapshot:<path>`.
@MainActor
enum MediaIslandDemo {
    static func run(_ browser: BrowserWindowController) async {
        let file = SessionStore.testDirectory.appending(path: "media-island.html")
        let audio = MediaFullscreenChecks.wave().base64EncodedString()
        let html = """
        <!doctype html><meta charset="utf-8"><title>Island Demo</title>
        <body style="font:20px system-ui;padding:60px"><h1>Island demo</h1>
        <audio loop src="data:audio/wav;base64,\(audio)"></audio>
        <button aria-label="Next track">Next</button>
        """
        do { try html.write(to: file, atomically: true, encoding: .utf8) } catch { return }
        browser.open(file.absoluteString, inNewTab: true)
        try? await Task.sleep(for: .milliseconds(800))
        guard let page = browser.activeController?.page else { print("IKTEST mediademo no page"); return }
        do {
            _ = try await page.callAsync("""
                navigator.mediaSession.metadata = new MediaMetadata({title: 'Midnight City', artist: 'M83',
                  artwork: [{src: 'https://picsum.photos/seed/ikago/96', sizes: '96x96'},
                            {src: 'https://picsum.photos/seed/ikago/512', sizes: '512x512'}]});
                const a = document.querySelector('audio'); a.volume = 0.01; await a.play(); return true;
                """)
        } catch { print("IKTEST mediademo play failed \(error)") }
        try? await Task.sleep(for: .seconds(2))
        let tab = browser.activeController?.tab
        print("IKTEST mediademo playing=\(tab?.playback.playing ?? false) title=\(tab?.playback.title ?? "") " +
              "artist=\(tab?.playback.artist ?? "") artwork=\(tab?.playback.artwork?.absoluteString ?? "nil")")
    }
}
#endif
