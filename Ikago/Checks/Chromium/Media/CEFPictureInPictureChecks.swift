import AppKit

/// Picture in Picture on Chromium (`ChromiumPictureInPicture`): the media button floats the playing video in Ikago's
/// panel with the page view, the tab shows its note, and Back to Tab puts the page and its video back. No Chromium window.
@MainActor
enum CEFPictureInPictureChecks {
    static func run(_ shell: BrowserWindowController, page: CEFWebTab) async throws {
        // A playing video Chromium decodes itself: a canvas stream (no media file or codec involved).
        _ = try await page.callAsync("""
            const canvas = document.createElement('canvas'); canvas.width = 320; canvas.height = 180;
            const context = canvas.getContext('2d'); let n = 0;
            setInterval(() => { context.fillStyle = `hsl(${(n += 7) % 360} 70% 50%)`; context.fillRect(0, 0, 320, 180); }, 30);
            const video = document.createElement('video'); video.id = 'ikago-pip-fixture'; video.muted = true;
            video.srcObject = canvas.captureStream(30); document.body.appendChild(video); await video.play();
            return true
            """)
        try await wait { (try? await page.callAsync("return document.getElementById('ikago-pip-fixture').videoWidth")) as? Int == 320 }
        let host = page.page.superview
        try await page.pictureInPicture()
        try await wait { page.floatingVideo.isActive && page.page.window?.title == "Picture in Picture" }
        guard (try await page.callAsync("return document.fullscreenElement?.id ?? ''")) as? String == "ikago-pip-fixture",
              host?.subviews.contains(where: { $0 !== page.page }) == true else {
            throw CEFError.script("Picture in Picture didn't float the video with its page.")
        }
        guard !NSApp.windows.contains(where: { $0.isVisible && ChromiumWindowGuard.isChromiumWindow($0) }) else {
            throw CEFError.script("Picture in Picture showed a Chromium window.")
        }
        try await page.pictureInPicture()  // the button again: Back to Tab
        try await wait { !page.floatingVideo.isActive && page.page.superview === host && page.page.window === shell.window }
        try await wait { (try? await page.callAsync("return document.fullscreenElement === null")) as? Bool == true }
        // The page's own PiP button (the standard API, as YouTube's): Chromium's window stays hidden and Ikago's panel takes over.
        _ = try await page.devTools("Runtime.evaluate", ["expression": "document.getElementById('ikago-pip-fixture').requestPictureInPicture()",
                                                         "awaitPromise": true, "userGesture": true])
        try await wait { page.floatingVideo.isActive && page.page.window?.title == "Picture in Picture" }
        guard !NSApp.windows.contains(where: { $0.isVisible && ChromiumWindowGuard.isChromiumWindow($0) }),
              (try await page.callAsync("return document.pictureInPictureElement === null && document.fullscreenElement?.id === 'ikago-pip-fixture'")) as? Bool == true else {
            throw CEFError.script("A page's own Picture in Picture didn't move into Ikago's panel.")
        }
        page.floatingVideo.end()
        try await wait { !page.floatingVideo.isActive && page.page.superview === host }
        _ = try await page.callAsync("document.getElementById('ikago-pip-fixture').remove(); return true")
    }

    private static func wait(_ condition: () async -> Bool) async throws {
        try await CEFWait.until("Picture in Picture timed out.") { await condition() }
    }
}
