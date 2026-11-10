#if DEBUG
import AppKit
import Foundation
import IKCEFBridge

@MainActor
enum MediaFullscreenChecks {
    static func run(_ browser: BrowserWindowController) async {
        var failures = 0
        func check(_ value: Bool, _ label: String) {
            print("IKTEST mediafullscreen \(value ? "PASS" : "FAIL") \(label)")
            if !value { failures += 1 }
        }
        func settle() async { try? await Task.sleep(for: .milliseconds(650)) }
        guard let window = browser.window, let background = window.contentView as? WindowBackgroundView else { return }
        let original = window.frame
        // Repeated window transitions must restore the shell, not accumulate a titlebar or camera-band gap.
        for layout in [TabLayout.vertical, .horizontal] {
            browser.state.tabLayout = layout
            for cycle in 0..<3 {
                window.toggleFullScreen(nil)
                await settle()
                background.layoutSubtreeIfNeeded()
                check(background.shell?.frame.height == background.bounds.height - background.shellTopInset,
                      "fullscreen shell fits \(layout) cycle \(cycle)")
                window.toggleFullScreen(nil)
                await settle()
                background.layoutSubtreeIfNeeded()
                check(background.shell?.frame == background.bounds && window.frame == original,
                      "window restores without padding \(layout) cycle \(cycle)")
            }
        }
        browser.state.tabLayout = .vertical
        let file = SessionStore.testDirectory.appending(path: "media-player.html")
        let audio = wave().base64EncodedString()
        let html = """
        <!doctype html><meta charset="utf-8"><title>Test Track · Ikago</title><style>body{font:24px system-ui;padding:60px;background:#fafafa}</style>
        <h1>Test Track</h1><audio controls loop src="data:audio/wav;base64,\(audio)"></audio>
        <button id="play" onclick="const a=document.querySelector('audio');a.volume=0.01;a.play()">Play</button>
        <button id="fullscreen" onclick="document.documentElement.requestFullscreen()">Fullscreen</button>
        <button aria-label="Next track" onclick="document.title='Next Track';document.querySelector('audio').pause()">Next</button>
        """
        do { try html.write(to: file, atomically: true, encoding: .utf8) } catch { check(false, "write media fixture"); return }
        browser.open(file.absoluteString, inNewTab: true)
        await settle()
        guard let controller = browser.activeController, let page = controller.page else { check(false, "fixture page starts"); return }
        let tab = controller.tab
        do {
            if page.engine == .webkit {
                _ = try await page.callAsync("const a=document.querySelector('audio');a.volume=0.01;await a.play();return true;")
            } else { try await click("play", page: page, window: window) }
        } catch { check(false, "fixture plays: \(error)") }
        try? await Task.sleep(for: .seconds(2))
        check(tab.isPlayingAudio && tab.playback.available && tab.playback.playing, "audible media reaches tab and player")
        browser.state.togglePin(tab.id)
        check(browser.state.pinnedTabs.contains { $0.id == tab.id && $0.isPlayingAudio }, "Essentials retain audio state")
        browser.toggleMute(tab.id)
        await settle()
        check(tab.isMuted && !tab.isPlayingAudio && tab.playback.available, "muting silences media and retains player")
        browser.toggleMute(tab.id)
        try? await Task.sleep(for: .seconds(2))
        check(!tab.isMuted && tab.isPlayingAudio, "unmuting restores sound")
        await page.controlMedia(.pause)
        await settle()
        check(tab.playback.available && !tab.playback.playing && !tab.isPlayingAudio, "pause retains a resumable player")
        await page.controlMedia(.play)
        await settle()
        check(tab.playback.playing, "player resumes playback")
        if let image = background.bitmapImageRepForCachingDisplay(in: background.bounds) {
            background.cacheDisplay(in: background.bounds, to: image)
            try? image.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/ikago-player-\(page.engine.rawValue).png"))
        }
        check(tab.playback.canGoNext, "supported next-track control detected")
        await page.controlMedia(.next)
        try? await Task.sleep(for: .seconds(2))
        check(tab.title == "Next Track" && !tab.playback.playing, "next invokes the page's track control")
        do {
            let source = Data(html.utf8).base64EncodedString()
            _ = try await page.callAsync("""
                document.querySelector('audio').remove();
                const frame = document.createElement('iframe');
                frame.style='width:700px;height:400px;display:block';
                frame.srcdoc = atob('\(source)');
                document.body.append(frame);
                await new Promise(resolve => frame.onload = resolve);
                return true;
                """)
            if page.engine == .webkit {
                _ = try await page.callAsync("const a=document.querySelector('iframe').contentDocument.querySelector('audio');a.volume=0.01;await a.play();return true;")
            } else { try await click("play", page: page, window: window, embedded: true) }
            try? await Task.sleep(for: .seconds(4))
            check(tab.isPlayingAudio && tab.playback.available, "embedded player reports audio")
            await page.controlMedia(.pause)
            try? await Task.sleep(for: .seconds(2))
            check(!tab.playback.playing && !tab.isPlayingAudio && tab.playback.available, "embedded player pauses from sidebar")
            await page.controlMedia(.play)
            try? await Task.sleep(for: .seconds(2))
            check(tab.playback.playing && tab.isPlayingAudio, "embedded player resumes from sidebar")
        } catch { check(false, "embedded media fixture: \(error)") }
        // Use real element fullscreen, which follows the same engine path as a video.
        for cycle in 0..<3 {
            do {
                try await click("fullscreen", page: page, window: window)
                try? await Task.sleep(for: .seconds(1))
                let entered = try await page.callAsync("return !!document.fullscreenElement") as? Bool == true
                check(entered, "element enters fullscreen cycle \(cycle)")
                _ = try await page.callAsync("await document.exitFullscreen(); return true;")
                try? await Task.sleep(for: .seconds(1))
                background.layoutSubtreeIfNeeded()
                check(background.shell?.frame == background.bounds, "element fullscreen restores without padding cycle \(cycle)")
            } catch { check(false, "element fullscreen: \(error)") }
        }
        controller.load("about:blank")
        await settle()
        check(!tab.playback.available && !tab.isPlayingAudio, "navigation clears old media")
        print("IKTEST mediafullscreenchecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }

    private static func click(_ id: String, page: WebTab, window: NSWindow, embedded: Bool = false) async throws {
        let script = embedded ? """
            const frame=document.querySelector('iframe'), f=frame.getBoundingClientRect();
            const r=frame.contentDocument.querySelector('#\(id)').getBoundingClientRect();
            return {x:f.x+r.x+r.width/2+frame.clientLeft,y:f.y+r.y+r.height/2+frame.clientTop};
            """ : "const r=document.querySelector('#\(id)').getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2};"
        guard let rect = try await page.callAsync(script) as? [String: Double], let x = rect["x"], let y = rect["y"] else { throw CocoaError(.coderInvalidValue) }
        let view = page.contentView
        let point = view.convert(NSPoint(x: x, y: view.isFlipped ? y : view.bounds.height - y), to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 1, clickCount: 1, pressure: 1) {
                if page.engine == .webkit {
                    if type == .leftMouseDown { view.mouseDown(with: event) } else { view.mouseUp(with: event) }
                } else { window.sendEvent(event) }
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    static func wave() -> Data {
        var data = Data()
        func string(_ value: String) { data.append(contentsOf: value.utf8) }
        func number<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        string("RIFF"); number(UInt32(36 + 16000)); string("WAVEfmt ")
        number(UInt32(16)); number(UInt16(1)); number(UInt16(1)); number(UInt32(8000))
        number(UInt32(16000)); number(UInt16(2)); number(UInt16(16)); string("data"); number(UInt32(16000))
        for sample in 0..<8000 { number(Int16(sin(Double(sample) * .pi * 2 * 220 / 8000) * 1000)) }
        return data
    }
}
#endif
