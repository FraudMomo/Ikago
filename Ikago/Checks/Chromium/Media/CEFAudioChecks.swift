import AppKit
import IKCEFBridge

/// Native Chromium audio must keep playing across tab mute/unmute, including muting before a stream starts.
@MainActor
enum CEFAudioChecks {
    static func run(_ page: IKCEFPage) async throws {
        page.audioMuted = true
        defer { page.audioMuted = false }
        guard page.audioMuted else { throw CEFError.script("Chromium did not mute before playback.") }
        let started = try await value(page, """
            (async () => {
              const rate = 48000, n = rate * 10, pcm = new Int16Array(n);
              for (let i = 0; i < n; i++) pcm[i] = Math.sin(2 * Math.PI * 220 * i / rate) * 12000;
              const header = new DataView(new ArrayBuffer(44));
              const text = (offset, value) => [...value].forEach((c, i) => header.setUint8(offset + i, c.charCodeAt(0)));
              text(0, 'RIFF'); header.setUint32(4, 36 + n * 2, true); text(8, 'WAVEfmt ');
              header.setUint32(16, 16, true); header.setUint16(20, 1, true); header.setUint16(22, 1, true);
              header.setUint32(24, rate, true); header.setUint32(28, rate * 2, true);
              header.setUint16(32, 2, true); header.setUint16(34, 16, true);
              text(36, 'data'); header.setUint32(40, n * 2, true);
              const audio = new Audio(URL.createObjectURL(new Blob([header, pcm], {type: 'audio/wav'})));
              audio.id = 'ikago-audio-check'; audio.volume = 0.005; document.body.append(audio);
              await audio.play(); return !audio.paused;
            })()
            """) as? Bool
        guard started == true else { throw CEFError.script("Native Chromium audio did not start.") }
        var before = 0.0
        for muted in [true, false, true, false] {
            page.audioMuted = muted
            var time = before
            try await CEFWait.until("Native tab mute/unmute interrupted Chromium playback or changed the media element.") {
                guard page.audioMuted == muted,
                      let state = try await value(page, """
                        (() => { const audio = document.getElementById('ikago-audio-check');
                          return {playing: !audio.paused && !audio.ended, time: audio.currentTime, muted: audio.muted}; })()
                        """) as? [String: Any],
                      state["playing"] as? Bool == true, state["muted"] as? Bool == false,
                      let now = state["time"] as? Double, now > before else { return false }
                time = now
                return true
            }
            before = time
        }
        _ = try await value(page, """
            (() => { const audio = document.getElementById('ikago-audio-check');
              audio.pause(); URL.revokeObjectURL(audio.src); audio.remove(); return true; })()
            """)
        try CEFHiddenServiceChecks.noVisibleChromiumWindows()
        print("CEF_AUDIO_OK native-playback mute-before-play mute-unmute keeps-playing")
    }

    private static func value(_ page: IKCEFPage, _ expression: String) async throws -> Any? {
        let result = try await CEFSmoke.method(page, "Runtime.evaluate", ["expression": expression,
            "returnByValue": true, "awaitPromise": true, "userGesture": true])
        guard result["exceptionDetails"] == nil else { throw CEFError.script("The native audio fixture failed.") }
        return (result["result"] as? [String: Any])?["value"]
    }
}
