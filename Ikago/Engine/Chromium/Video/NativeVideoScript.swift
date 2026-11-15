/// Finds videos Chromium can't play here (H.264/AAC are missing from the prebuilt CEF) so Ikago can play
/// them with macOS's own player on top. Runs in the "ikago-media" isolated world of the top document;
/// the page can't see it, and it never sends anything: native code polls `scan()`.
enum NativeVideoScript {
    static let world = "ikago-media"

    static let source = #"""
    (() => {
      if (window.__ikagoMedia || window !== window.top) return
      const thumb = /^https:\/\/pbs\.twimg\.com\/(ext_tw_video_thumb|amplify_video_thumb|tweet_video_thumb)\/([^/?#]+)/
      const onX = /(^|\.)(x|twitter)\.com$/.test(location.hostname)
      const token = id => ((Number(id) / 1e15) * Math.PI).toString(36).replace(/(0+|\.)/g, '')
      // key → {box: WeakRef, kind, src, status, token, thumb, media}; box → key
      const tracked = new Map(), keys = new WeakMap()
      // Videos already handled. X changes its DOM all the time while scrolling, so register() must stay cheap:
      // measuring an element forces the page to lay out.
      const known = new WeakSet()
      let next = 0

      // The tweet a video belongs to: the status link with its timestamp, else the tweet's first status link.
      const status = video => {
        const article = video.closest('article')
        if (article) {
          let first = null
          for (const link of article.querySelectorAll('a[href*="/status/"]')) {
            const match = (link.getAttribute('href') || '').match(/\/status\/(\d{1,25})(?:[/?#]|$)/)
            if (!match) continue
            if (link.querySelector('time')) return match[1]
            first = first || match[1]
          }
          if (first) return first
        }
        const page = location.pathname.match(/\/status\/(\d{1,25})/)
        return page ? page[1] : null
      }

      // X's player: the outermost element exactly the video's size. It outlives the <video>, which X
      // replaces with "The media could not be played" when Chromium gives up.
      const playerBox = video => {
        const r = video.getBoundingClientRect()
        let box = video
        for (let a = video.parentElement, i = 0; a && a !== document.body && i < 8; a = a.parentElement, i++) {
          const q = a.getBoundingClientRect()
          if (Math.abs(q.width - r.width) > 2 || Math.abs(q.height - r.height) > 2) break
          box = a
        }
        return box
      }

      // Chromium gave up on its source: H.264 or AAC in an MP4, or HLS.
      const unplayable = video => (video.error && video.error.code === 4) || video.networkState === 3

      const register = () => {
        for (const video of document.querySelectorAll('video')) {
          if (known.has(video)) continue
          const poster = (video.poster || '').match(thumb)
          let info = null
          if (onX && poster) {
            const id = status(video)
            info = {kind: 'x', src: '', status: id, token: id ? token(id) : null, thumb: poster[1], media: poster[2]}
          } else {
            const candidate = video.currentSrc || video.src || (video.querySelector('source[src]') || {}).src || ''
            if (candidate.startsWith('https:') && unplayable(video)) info = {kind: 'direct', src: candidate}
          }
          if (!info) continue
          const r = video.getBoundingClientRect()
          if (r.width < 40 || r.height < 30) continue
          known.add(video)
          const box = info.kind === 'x' ? playerBox(video) : video
          if (keys.has(box)) continue
          keys.set(box, ++next)
          tracked.set(next, Object.assign({box: new WeakRef(box), video: new WeakRef(video), since: Date.now()}, info))
        }
      }
      let queued = false
      new MutationObserver(() => {
        if (queued) return
        queued = true
        setTimeout(() => { queued = false; register() }, 250)
      }).observe(document.documentElement, {childList: true, subtree: true})
      register()

      // The page's player can't play it after all: the translation layer gave up, the video errored or vanished
      // (X swaps in "The media could not be played"), or it never got going. The native player then takes over.
      const stalled = (entry, box) => {
        const video = entry.video.deref()
        if (box.querySelector && box.querySelector('video[data-ikago-native]')) return true
        if (!video || !video.isConnected || !box.contains(video)) return true
        if (video.getAttribute('data-ikago-native') === '1' || video.error) return true
        return video.readyState === 0 && Date.now() - entry.since > 6000
      }

      // How far down the top edge is hidden by something else, such as X's sticky header.
      const hiddenTop = (box, r, vh) => {
        const x = Math.min(Math.max(r.left + r.width / 2, 0), innerWidth - 1)
        let y = Math.max(r.top, 0)
        const end = Math.min(r.bottom, vh) - 1
        while (y < end) {
          const hit = document.elementFromPoint(x, y)
          if (!hit || box.contains(hit)) break
          y += 6
        }
        return Math.max(0, y - r.top)
      }

      window.__ikagoMedia = {
        // `translating`: X's own player plays its videos through the translation layer, so leave them alone.
        scan: translating => {
          register()
          const out = [], vh = innerHeight, vw = innerWidth
          for (const [key, entry] of tracked) {
            const box = entry.box.deref()
            if (!box || !box.isConnected) { tracked.delete(key); continue }
            const r = box.getBoundingClientRect()
            if (r.width < 40 || r.height < 30 || r.bottom <= 0 || r.top >= vh || r.right <= 0 || r.left >= vw) continue
            const fallback = stalled(entry, box)
            // Only when the native player takes over: keep the page's own copy silent then, and never otherwise.
            if (entry.kind === 'direct' || !translating || fallback)
              for (const video of box.querySelectorAll ? box.querySelectorAll('video') : []) if (!video.paused) video.pause()
            const shown = (Math.min(r.bottom, vh) - Math.max(r.top, 0)) * (Math.min(r.right, vw) - Math.max(r.left, 0)) / (r.width * r.height)
            // X plays it itself: the native side ignores its geometry, so skip the hit tests.
            const placed = entry.kind === 'direct' || !translating || fallback
            const cx = Math.min(Math.max(r.left + r.width / 2, 0), vw - 1), cy = Math.min(Math.max(r.top + r.height / 2, 0), vh - 1)
            const middle = placed ? document.elementFromPoint(cx, cy) : null
            out.push({
              key, kind: entry.kind, src: entry.src, x: r.left, y: r.top, width: r.width, height: r.height,
              shown, covered: !!middle && !box.contains(middle) && middle !== box,
              hiddenTop: placed ? hiddenTop(box, r, vh) : 0,
              // The translation layer gave up on it (MediaTranslationShim), so the native player should play it.
              fallback,
              status: entry.status || null, token: entry.token || null, thumb: entry.thumb || null, media: entry.media || null
            })
          }
          return out
        }
      }
    })()
    """#
}
