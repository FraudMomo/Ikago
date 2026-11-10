import Foundation

struct MediaPlaybackState: Equatable {
    var available = false
    var playing = false
    var canGoNext = false
    var title = ""
    /// From the page's Media Session, when it sets one (music sites do).
    var artist = ""
    /// The Media Session's largest artwork, HTTPS only; loaded without cookies (`MediaArtwork`).
    var artwork: URL?

    init() {}
    init(_ report: [String: Any]) {
        available = report["available"] as? Bool ?? false
        playing = report["playing"] as? Bool ?? false
        canGoNext = report["canGoNext"] as? Bool ?? false
        title = String((report["title"] as? String ?? "").prefix(300))
        artist = String((report["artist"] as? String ?? "").prefix(200))
        artwork = (report["artwork"] as? String).flatMap(URL.init(string:)).flatMap { $0.scheme == "https" ? $0 : nil }
    }
}

enum MediaPlaybackAction: String { case play, pause, next }

/// Shared DOM controls, always installed in the engine's isolated browser world.
/// Only media which has produced sound becomes a player; silent autoplay previews stay out.
enum MediaPlaybackScript {
    static let install = """
    (() => {
      if (window.__ikagoMedia) return;
      const heard = new WeakSet(), previousMute = new WeakMap();
      let tabMuted = false;
      const elements = () => [...document.querySelectorAll('audio,video')];
      const playing = m => !m.paused && !m.ended;
      const next = () => [...document.querySelectorAll(
        '.ytp-next-button, [data-testid="control-button-skip-forward"], button[aria-label="Next track"], button[aria-label="Next video"]'
      )].find(b => !b.disabled && b.getAttribute('aria-disabled') !== 'true' && b.getClientRects().length);
      const state = () => {
        const all = elements();
        for (const m of all) if (playing(m) && !m.muted && m.volume > 0) heard.add(m);
        const media = all.filter(m => heard.has(m) && (m.currentSrc || m.srcObject));
        const meta = navigator.mediaSession?.metadata;
        const size = a => Math.max(0, ...String(a.sizes || '').split(/\\s+/).map(s => parseInt(s, 10) || 0));
        const art = [...(meta?.artwork || [])].filter(a => /^https:/.test(a.src || '')).sort((a, b) => size(b) - size(a))[0];
        return {audible: all.some(m => playing(m) && !m.muted && m.volume > 0),
          available: media.length > 0, playing: media.some(playing),
          canGoNext: !!next(), title: meta?.title || document.title,
          artist: meta?.artist || '', artwork: art?.src || ''};
      };
      const mute = value => {
        tabMuted = value;
        for (const m of elements()) {
          if (value) {
            if (!previousMute.has(m)) previousMute.set(m, m.muted);
            m.muted = true;
          } else if (previousMute.has(m)) {
            m.muted = previousMute.get(m); previousMute.delete(m);
          }
        }
      };
      const control = async action => {
        const media = elements().filter(m => heard.has(m));
        if (action === 'pause') { for (const m of media) m.pause(); }
        if (action === 'play') {
          const m = media.find(playing) || media[0];
          if (m) await m.play();
        }
        if (action === 'next') next()?.click();
      };
      window.__ikagoMedia = {state, mute, control};
      new MutationObserver(changes => {
        if (changes.some(c => [...c.addedNodes, ...c.removedNodes].some(n =>
          n.nodeType === 1 && (n.matches('audio,video') || n.querySelector('audio,video'))))) {
          state();
          if (tabMuted) mute(true);
          window.__ikagoMediaChanged?.();
        }
      }).observe(document, {childList: true, subtree: true});
      for (const type of ['play','playing','pause','ended','emptied','volumechange','loadedmetadata']) {
        document.addEventListener(type, event => {
          // Remember a newly audible element before tab muting changes its volume.
          state();
          if (tabMuted && type === 'play') mute(true);
          window.__ikagoMediaChanged?.();
        }, true);
      }
    })();
    """

    static func control(_ action: MediaPlaybackAction) -> String {
        "\(install)\nawait window.__ikagoMedia.control('\(action.rawValue)'); return window.__ikagoMedia.state();"
    }
}
