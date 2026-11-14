import Foundation

struct MediaPlaybackState: Equatable {
    var available = false
    var playing = false
    var canGoNext = false
    var hasVideo = false
    var title = ""
    /// From the page's Media Session, when it sets one (music sites do).
    var artist = ""
    /// Media Session artwork, a media poster or the page's thumbnail, HTTPS only; loaded without cookies (`MediaArtwork`).
    var artwork: URL?

    init() {}
    init(_ report: [String: Any]) {
        available = report["available"] as? Bool ?? false
        playing = report["playing"] as? Bool ?? false
        hasVideo = report["hasVideo"] as? Bool ?? false
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
      // The document and every open shadow root found in it: players built as web components keep their <video>
      // in a shadow root, which document.querySelectorAll doesn't reach and whose media events don't leave it.
      const roots = new Set();
      const elements = () => [...roots].flatMap(root => [...root.querySelectorAll('audio,video')]);
      const playing = m => !m.paused && !m.ended;
      const imageURL = source => {
        if (typeof source !== 'string' || !source.trim()) return '';
        try {
          const url = new URL(source, document.baseURI);
          return url.protocol === 'https:' && !url.username && !url.password ? url.href : '';
        } catch { return ''; }
      };
      const next = () => [...document.querySelectorAll(
        '.ytp-next-button, [data-testid="control-button-skip-forward"], button[aria-label="Next track"], button[aria-label="Next video"]'
      // No getClientRects here: it forces a layout, and reports come during scrolling (a grid of autoplaying videos).
      )].find(b => !b.disabled && b.getAttribute('aria-disabled') !== 'true' && b.style.display !== 'none' && !b.hidden);
      const state = () => {
        const all = elements();
        for (const m of all) if (playing(m) && !m.muted && m.volume > 0) heard.add(m);
        const media = all.filter(m => heard.has(m) && (m.currentSrc || m.srcObject));
        const meta = navigator.mediaSession?.metadata;
        const size = a => Math.max(0, ...String(a.sizes || '').split(/\\s+/).map(s => parseInt(s, 10) || 0));
        // Chromium's isolated world can lack the page's Media Session metadata. Posters and document metadata are
        // shared DOM, so artwork still works without running browser scripts in the page's world.
        // Artwork only matters for media the island shows; skip the document-wide lookups otherwise.
        const art = !media.length ? '' : [...(meta?.artwork || [])].sort((a, b) => size(b) - size(a))
          .map(a => imageURL(a.src)).find(Boolean)
          || imageURL((media.find(playing) || media[0])?.poster)
          || [...document.querySelectorAll('meta[property="og:image:secure_url"], meta[property="og:image"], meta[name="twitter:image"], meta[name="twitter:image:src"], link[rel="image_src"], link[itemprop="thumbnailUrl"]')]
            .map(element => imageURL(element.content || element.getAttribute('href'))).find(Boolean)
          || '';
        return {audible: all.some(m => playing(m) && !m.muted && m.volume > 0),
          available: media.length > 0, playing: media.some(playing),
          hasVideo: media.some(m => m.tagName === 'VIDEO'),
          canGoNext: media.length > 0 && !!next(), title: meta?.title || document.title,
          artist: meta?.artist || '', artwork: art,
          unsupportedVideo: all.some(m => m.tagName === 'VIDEO' && !!m.error)};
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
        const media = action === 'pause' ? elements() : elements().filter(m => heard.has(m));
        if (action === 'pause') { for (const m of media) m.pause(); }
        if (action === 'play') {
          const m = media.find(playing) || media[0];
          if (m) await m.play();
        }
        if (action === 'next') next()?.click();
      };
      window.__ikagoMedia = {state, mute, control};
      // Shadow roots belong to custom elements (a hyphen in the name); only those are checked.
      const scan = node => {
        if (![1, 9, 11].includes(node.nodeType)) return;
        if (node.nodeType === 1 && node.localName.includes('-') && node.shadowRoot) watch(node.shadowRoot);
        const walker = document.createTreeWalker(node, NodeFilter.SHOW_ELEMENT, {
          acceptNode: e => e.localName.includes('-') && e.shadowRoot ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_SKIP
        });
        while (walker.nextNode()) watch(walker.currentNode.shadowRoot);
      };
      const watch = root => {
        if (roots.has(root)) return;
        roots.add(root);
        // Pages like Pinterest add and remove thousands of elements while scrolling: note what was added and look at
        // it once a quarter second, instead of walking every subtree as it arrives.
        new MutationObserver(changes => {
          for (const c of changes) {
            for (const n of c.addedNodes) if (n.nodeType === 1) pendingNodes.add(n);
            if (!removedMedia) for (const n of c.removedNodes)
              if (n.nodeType === 1 && (n.localName === 'video' || n.localName === 'audio' || n.firstElementChild)) { removedMedia = true; break; }
          }
          if (!flushTimer) flushTimer = setTimeout(flush, 250);
        }).observe(root, {childList: true, subtree: true});
        for (const type of ['play','playing','pause','ended','emptied','volumechange','loadedmetadata','durationchange','error']) {
          root.addEventListener(type, event => {
            const media = event.composedPath()[0];
            if (!(media instanceof HTMLMediaElement)) return;
            // Remember a newly audible element before tab muting changes its volume.
            if (playing(media) && !media.muted && media.volume > 0) heard.add(media);
            if (tabMuted && type === 'play') mute(true);
            // Silent autoplay previews (a feed of video pins) start and stop constantly while scrolling and are never
            // shown: only media that has been heard, and errors (unsupported video), are worth a report.
            if (heard.has(media) || type === 'error' || type === 'volumechange') window.__ikagoMediaChanged?.();
          }, true);
        }
        scan(root);
      };
      let pendingNodes = new Set(), removedMedia = false, flushTimer = 0, mediaCount = -1;
      // Only media that has been heard is shown, so only those coming and going need a report.
      const countMedia = () => elements().reduce((n, m) => n + (heard.has(m) ? 1 : 0), 0);
      const flush = () => {
        flushTimer = 0;
        const nodes = [...pendingNodes].filter(n => n.isConnected);
        pendingNodes = new Set();
        // Only the added elements themselves are checked for a shadow root: walking every added subtree in script
        // cost a call per element on infinite feeds. Deeper players are found by rescan (load, clicks, keys).
        let media = removedMedia;
        for (const n of nodes) {
          if (n.localName.includes('-') && n.shadowRoot) watch(n.shadowRoot);
          if (!media && (n.localName === 'video' || n.localName === 'audio' || n.querySelector('audio,video'))) media = true;
        }
        const count = media ? countMedia() : mediaCount;
        removedMedia = false;
        if (media && tabMuted) mute(true);
        if (count === mediaCount) return;
        mediaCount = count;
        window.__ikagoMediaChanged?.();
      };
      watch(document);
      // An element upgraded after it was inserted gets its shadow root without any mutation the observers see.
      // Look again when the page finishes loading and after the person clicks or types (when sound usually starts),
      // at most once a second; no clock.
      let lastScan = 0;
      const rescan = () => {
        const now = Date.now();
        if (now - lastScan < 1000) return;
        lastScan = now;
        const before = roots.size;
        scan(document);
        if (roots.size !== before) window.__ikagoMediaChanged?.();
      };
      document.addEventListener('DOMContentLoaded', () => { lastScan = 0; rescan(); }, {once: true});
      addEventListener('load', () => { lastScan = 0; rescan(); }, {once: true});
      for (const type of ['pointerup', 'keyup']) document.addEventListener(type, rescan, {capture: true, passive: true});
    })();
    """

    static func control(_ action: MediaPlaybackAction) -> String {
        "\(install)\nawait window.__ikagoMedia.control('\(action.rawValue)'); return window.__ikagoMedia.state();"
    }
}
