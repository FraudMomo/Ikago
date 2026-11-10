import AppKit
import IKCEFBridge

/// `--cef-smoke-audio`: plays a quiet track in a hidden page and reports what Ikago's own playback of Chromium's sound
/// (IKCEFAudio) adds in delay, and whether the wave's band levels follow the sound.
@MainActor
enum CEFAudioProbe {
    static func run() async -> Int32 {
        setvbuf(stdout, nil, _IOLBF, 0)
        do {
            try CEFSessions.prepare("Audio")
            // `--cef-smoke-audio-off` checks that the default leaves Chromium’s own playback alone.
            IKCEFAudio.enabled = !CommandLine.arguments.contains("--cef-smoke-audio-off")
            let page = try IKCEFPage.make(profile: "Audio")
            defer { page.close() }
            let host = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
            host.contentView = page
            for _ in 0..<200 where !page.ready { try await Task.sleep(for: .milliseconds(50)) }
            page.loadURL("about:blank")
            try await Task.sleep(for: .seconds(1))
            // Two seconds of a tone that alternates between bass and treble every quarter second, looped.
            let script = """
            (async () => {
              const rate = 48000, n = rate * 2, pcm = new Int16Array(n);
              for (let i = 0; i < n; i++) { const t = i / rate, hi = Math.floor(t * 4) % 2;
                pcm[i] = Math.sin(2 * Math.PI * (hi ? 6000 : 110) * t) * 12000; }
              const header = new DataView(new ArrayBuffer(44)), s = (o, v) => [...v].forEach((c, k) => header.setUint8(o + k, c.charCodeAt(0)));
              s(0, 'RIFF'); header.setUint32(4, 36 + n * 2, true); s(8, 'WAVEfmt '); header.setUint32(16, 16, true);
              header.setUint16(20, 1, true); header.setUint16(22, 1, true); header.setUint32(24, rate, true);
              header.setUint32(28, rate * 2, true); header.setUint16(32, 2, true); header.setUint16(34, 16, true);
              s(36, 'data'); header.setUint32(40, n * 2, true);
              const audio = new Audio(URL.createObjectURL(new Blob([header, pcm], {type: 'audio/wav'})));
              audio.loop = true; audio.volume = 0.02; document.body.append(audio);
              await audio.play(); return 'playing';
            })()
            """
            let result = try await HiddenChromiumPage.call(page, "Runtime.evaluate", ["expression": script, "awaitPromise": true, "returnByValue": true, "userGesture": true])
            print("CEF_AUDIO play \((result["result"] as? [String: Any])?["value"] ?? result)")
            for step in 0..<24 {
                try await Task.sleep(for: .milliseconds(125))
                let levels = IKCEFAudio.levels(forBrowser: page.browserIdentifier)?.map { String(format: "%.2f", $0.doubleValue) } ?? []
                print("CEF_AUDIO levels t=\(step * 125)ms \(levels.joined(separator: " "))")
            }
            print("CEF_AUDIO latency \(IKCEFAudio.latencyReport())")
            return 0
        } catch {
            print("CEF_AUDIO failed \(error)")
            return 1
        }
    }
}
