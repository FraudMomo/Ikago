/// The page half of the media translation layer (X only, on by default). It runs in X's own world before X's
/// scripts, because the player it serves lives there: Media Source reports H.264/AAC in MP4 as supported, and a
/// SourceBuffer for them is really an AV1/FLAC one whose appends go through Ikago (`/__ikago_media__` on the
/// page's own origin, as GET parts, answered natively; see `IKCEFMediaBridge`). Everything else is the player's own code, so
/// its controls, seeking, quality switching and autoplay keep working.
///
/// This is the one browser script outside an isolated world (AGENTS.md §3.6 exception): it only rewires the
/// page's own media, and a page that tampers with it only affects its own videos.
enum MediaTranslationShim {
    static let hosts = ["x.com", "twitter.com"]

    static let source = #"""
    (() => {
      if (!/(^|\.)(x|twitter)\.com$/.test(location.hostname) || window.__ikagoMediaTranslation) return
      const MS = window.MediaSource
      if (!MS || !window.SourceBuffer) return
      Object.defineProperty(window, '__ikagoMediaTranslation', {value: true})
      const supported = MS.isTypeSupported.bind(MS)
      const addSourceBuffer = MS.prototype.addSourceBuffer, removeSourceBuffer = MS.prototype.removeSourceBuffer
      const real = new WeakMap(), blobs = new WeakMap()
      const createObjectURL = URL.createObjectURL
      URL.createObjectURL = function (object) {
        const url = createObjectURL.call(URL, object)
        if (object instanceof MS) blobs.set(object, url)
        return url
      }
      const videoOf = source => {
        const url = blobs.get(source)
        if (url) for (const video of document.querySelectorAll('video')) if (video.src === url) return video
        return null
      }
      // Ikago couldn't translate this video: mark it so the native player takes over.
      const giveUp = source => { const video = videoOf(source); if (video) video.setAttribute('data-ikago-native', '1') }

      // How Ikago should treat this append. urgent: the player is (or soon will be) waiting for it, so translate on every
      // core; otherwise it's buffered ahead and runs on the efficiency cores. fit: the video's shorter on-screen side in
      // device pixels, so a large source shown small is encoded at 720p.
      const hints = source => {
        const video = videoOf(source)
        if (!video) return '&urgent=1&fit=0'
        const time = video.currentTime, ranges = video.buffered
        let ahead = 0
        for (let i = 0; i < ranges.length; i++) if (ranges.start(i) <= time + 0.5 && ranges.end(i) > time) ahead = ranges.end(i) - time
        const urgent = video.seeking || ahead === 0 || (!video.paused && ahead < 5)
        const r = video.getBoundingClientRect()
        const fit = Math.max(0, Math.min(16384, Math.round(Math.min(r.width, r.height) * (window.devicePixelRatio || 1))))
        return '&urgent=' + (urgent ? 1 : 0) + '&fit=' + fit
      }

      // 'video/mp4; codecs="avc1.640028"' → what this Chromium plays instead, or null to leave it alone.
      const translated = type => {
        const match = /^\s*(video|audio)\/mp4\s*;\s*codecs\s*=\s*"?([^"]*)"?\s*$/i.exec(type || '')
        if (!match) return null
        const codecs = match[2].split(',').map(c => c.trim()).filter(Boolean)
        const video = codecs.filter(c => /^avc[13]\./i.test(c)).length, audio = codecs.filter(c => /^mp4a\.40\./i.test(c)).length
        if (video + audio !== codecs.length || video + audio !== 1) return null  // one H.264 or one AAC track per buffer
        return video ? 'video/mp4; codecs="av01.0.13M.08"' : 'audio/mp4; codecs="flac"'
      }

      // Players also ask about H.264 and AAC together before choosing separate video and audio buffers.
      const muxed = type => {
        const match = /^\s*video\/mp4\s*;\s*codecs\s*=\s*"?([^"]*)"?\s*$/i.exec(type || '')
        if (!match) return false
        const codecs = match[1].split(',').map(c => c.trim()).filter(Boolean)
        return codecs.length === 2 && codecs.some(c => /^avc[13]\./i.test(c)) && codecs.some(c => /^mp4a\.40\./i.test(c))
      }
      MS.isTypeSupported = function isTypeSupported(type) {
        const instead = translated(type)
        if (!instead && muxed(type)) return supported('video/mp4; codecs="av01.0.13M.08"') && supported('audio/mp4; codecs="flac"')
        return instead ? supported(instead) : supported(type)
      }

      // A segment travels as base64url parts in GET requests: service workers (X has one) don't pass request
      // bodies on. Ikago answers each part on this origin and returns the translated segment for the last one.
      let sequence = 0
      const base64url = bytes => {
        if (bytes.toBase64) return bytes.toBase64({ alphabet: 'base64url', omitPadding: true })  // native: no string building on the page's thread
        let text = ''
        for (let i = 0; i < bytes.length; i += 0x8000) text += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000))
        return btoa(text).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
      }
      const send = async (stream, bytes, signal, extra) => {
        const seq = ++sequence, size = 384 * 1024, parts = Math.max(1, Math.ceil(bytes.byteLength / size))
        let response = null
        for (let part = 0; part < parts; part++) {
          const chunk = new Uint8Array(bytes, part * size, Math.min(size, bytes.byteLength - part * size))
          response = await fetch('/__ikago_media__?stream=' + stream + '&seq=' + seq + '&part=' + part + '&parts=' + parts +
                                 (part === parts - 1 ? extra : '') + '&data=' + base64url(chunk),
                                 { signal, credentials: 'omit', cache: 'no-store' })
          if (!response.ok) throw new Error('translation failed')
        }
        return response.arrayBuffer()
      }

      const stream = () => (crypto.randomUUID ? crypto.randomUUID() : String(Math.random()).slice(2))

      const wrap = (buffer, instead, source) => {
        const events = new EventTarget()
        const proxy = Object.create(SourceBuffer.prototype)
        const id = stream()
        let pending = null, translating = !!instead, handlers = {}
        const fire = name => {
          const event = new Event(name)
          events.dispatchEvent(event)
          if (typeof handlers[name] === 'function') handlers[name].call(proxy, event)
        }
        for (const name of ['updatestart', 'update', 'updateend', 'error', 'abort']) {
          buffer.addEventListener(name, () => fire(name))
          Object.defineProperty(proxy, 'on' + name, { get: () => handlers[name] || null, set: f => { handlers[name] = f }, configurable: true })
        }
        const forward = name => Object.defineProperty(proxy, name, {
          get: () => buffer[name], set: value => { buffer[name] = value }, configurable: true, enumerable: true
        })
        for (const name of ['mode', 'timestampOffset', 'appendWindowStart', 'appendWindowEnd']) forward(name)
        for (const name of ['buffered', 'audioTracks', 'videoTracks', 'textTracks'])
          Object.defineProperty(proxy, name, { get: () => buffer[name], configurable: true, enumerable: true })
        Object.defineProperty(proxy, 'updating', { get: () => !!pending || buffer.updating, configurable: true, enumerable: true })
        Object.assign(proxy, {
          addEventListener: (...a) => events.addEventListener(...a),
          removeEventListener: (...a) => events.removeEventListener(...a),
          dispatchEvent: e => events.dispatchEvent(e),
          appendBuffer(data) {
            if (pending || buffer.updating) throw new DOMException('The SourceBuffer is still updating.', 'InvalidStateError')
            if (!translating) return buffer.appendBuffer(data)
            const bytes = data instanceof ArrayBuffer ? data.slice(0) : data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength)
            const controller = new AbortController()
            pending = controller
            send(id, bytes, controller.signal, hints(source)).then(result => {
              if (pending !== controller) return
              pending = null
              if (result.byteLength) buffer.appendBuffer(result)
              else { fire('updatestart'); fire('update'); fire('updateend') }
            }).catch(() => {
              if (pending !== controller) return
              pending = null
              giveUp(source)
              fire('error'); fire('updateend')
            })
          },
          abort() {
            if (pending) { pending.abort(); pending = null; fire('abort'); fire('updateend') }
            if (buffer.updating) buffer.abort()
            else try { buffer.abort() } catch (_) {}
          },
          remove: (start, end) => buffer.remove(start, end),
          changeType(type) {
            const next = translated(type)
            translating = !!next
            buffer.changeType(next || type)
          }
        })
        real.set(proxy, buffer)
        return proxy
      }

      MS.prototype.addSourceBuffer = function addSourceBuffer_(type) {
        const instead = translated(type)
        if (!instead) return addSourceBuffer.call(this, type)
        return wrap(addSourceBuffer.call(this, instead), instead, this)
      }
      MS.prototype.removeSourceBuffer = function removeSourceBuffer_(buffer) {
        return removeSourceBuffer.call(this, real.get(buffer) || buffer)
      }
    })()
    """#
}
