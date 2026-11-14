#if DEBUG
import AppKit

/// WebKit Picture in Picture: pages may use it (`MediaPictureInPicture.allow`), and the media island's button opens and
/// closes it for a playing video, including a stream with no file address (as YouTube's `blob:` media).
@MainActor
enum PictureInPictureChecks {
    static func run(_ browser: BrowserWindowController) async {
        var failures = 0
        func check(_ value: Bool, _ title: String) {
            print("IKTEST pip \(value ? "PASS" : "FAIL") \(title)")
            if !value { failures += 1 }
        }
        defer { print("IKTEST pipchecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)") }
        guard let tab = browser.state.newTab(url: "about:blank") else { return check(false, "opens a tab") }
        try? await Task.sleep(for: .seconds(1))
        guard let page = browser.content.controller(for: tab.id)?.page else { return check(false, "the tab has a page") }
        let ready = try? await page.callAsync("""
            const canvas = document.createElement('canvas'); canvas.width = 320; canvas.height = 180;
            const context = canvas.getContext('2d'); let n = 0;
            setInterval(() => { context.fillStyle = `hsl(${(n += 7) % 360} 70% 50%)`; context.fillRect(0, 0, 320, 180); }, 30);
            const video = document.createElement('video'); video.muted = true; video.playsInline = true;
            video.srcObject = canvas.captureStream(30); document.body.appendChild(video); await video.play();
            await new Promise(r => setTimeout(r, 500));
            return video.webkitSupportsPresentationMode('picture-in-picture') && document.pictureInPictureEnabled
            """) as? Bool
        check(ready == true, "pages may use Picture in Picture")
        func mode() async -> String { (try? await page.callAsync("return document.querySelector('video').webkitPresentationMode")) as? String ?? "" }
        browser.pictureInPicture(tab.id)
        for _ in 0..<40 where await mode() != "picture-in-picture" { try? await Task.sleep(for: .milliseconds(100)) }
        check(await mode() == "picture-in-picture", "the PiP button floats a stream with no file address")
        browser.pictureInPicture(tab.id)
        for _ in 0..<40 where await mode() != "inline" { try? await Task.sleep(for: .milliseconds(100)) }
        check(await mode() == "inline", "the button again puts it back in the page")
        browser.closeTab(tab.id)
    }
}
#endif
