/// The key button Ikago shows in sign-in fields. It runs in an isolated world, never
/// the page's: WebKit's `.defaultClient` world in every frame, or on Chromium the "ikago-passwords" world
/// of the main frame. Native code decides whether a frame may show it, and only a trusted click asks
/// native code to fill: Apple's panel, or a login from Ikago's vault after Touch ID, which native code
/// passes to `fill`. The DOM is built without innerHTML so pages that require Trusted Types keep working.
enum PasswordKeyScript {
    /// WebKit: replies come back through the message handler's promise.
    static let source = make(transport: "const post = message => window.webkit.messageHandlers.\(PasswordAutoFill.handlerName).postMessage(message)",
                             mainFrameOnly: false)

    /// Chromium: injected only where the vault has a login, so the key may always show. The script never
    /// sends anything: native code sees the real click and asks `hit` whether it landed on the key.
    static let chromium = make(transport: "const post = message => Promise.resolve(message.type === 'query')", mainFrameOnly: true)

    private static func make(transport: String, mainFrameOnly: Bool) -> String { """
        (() => {
          if (window.__ikagoPasswordKey\(mainFrameOnly ? " || window !== window.top" : "")) return
          \(transport)
          const handler = { postMessage: post }
          const largest = 22, smallest = 12, inset = 3, minimumWidth = 80
          const textTypes = new Set(['', 'text', 'email', 'tel'])
          const userPattern = /user|login|e-?mail|account|identifier/i
          let field = null, requested = null, requests = 0

          const typeOf = el => (el.getAttribute('type') || '').toLowerCase()
          const tokens = el => (el.getAttribute('autocomplete') || '').toLowerCase().split(/\\s+/)
          const visible = el => { const r = el.getBoundingClientRect(); return r.width > 0 && r.height > 0 }
          const textFields = scope => [...scope.querySelectorAll('input')]
            .filter(el => textTypes.has(typeOf(el)) && visible(el))
          // Passwords, annotated usernames, and username-like fields in a password form or a
          // one-field "enter your email" step.
          const isLoginField = el => {
            if (!(el instanceof HTMLInputElement) || el.disabled || el.readOnly) return false
            const type = typeOf(el)
            if (type === 'password') return true
            if (!textTypes.has(type)) return false
            if (tokens(el).some(t => t === 'username' || t === 'webauthn')) return true
            const identity = [el.name, el.id, el.getAttribute('autocomplete') || '', type === 'email' ? 'email' : ''].join(' ')
            if (!userPattern.test(identity)) return false
            const scope = el.form || document
            return !!scope.querySelector('input[type=password i]') || textFields(scope).length === 1
          }

          const host = document.createElement('ikago-password-key')
          const root = host.attachShadow({ mode: 'closed' })
          const style = document.createElement('style')
          style.textContent = `
            button { all: initial; box-sizing: border-box; width: 100%; height: 100%; border-radius: 5px;
              display: grid; place-items: center; cursor: default; color: #3c3c43; background: rgba(255,255,255,.92);
              border: 1px solid rgba(0,0,0,.14); box-shadow: 0 1px 2px rgba(0,0,0,.12) }
            button:hover { background: #fff; color: #000 }
            @media (prefers-color-scheme: dark) {
              button { color: #ebebf5; background: rgba(44,44,46,.92); border-color: rgba(255,255,255,.18) }
              button:hover { background: #3a3a3c; color: #fff }
            }
            svg { width: 64%; height: 64%; fill: none; stroke: currentColor; stroke-width: 1.6; stroke-linecap: round }`
          const button = document.createElement('button')
          button.type = 'button'
          button.title = 'Fill from Passwords'
          button.setAttribute('aria-label', 'Fill from Passwords')
          const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg')
          svg.setAttribute('viewBox', '0 0 16 16')
          const ring = document.createElementNS('http://www.w3.org/2000/svg', 'circle')
          for (const [name, value] of [['cx', '4.8'], ['cy', '8'], ['r', '3']]) ring.setAttribute(name, value)
          const shaft = document.createElementNS('http://www.w3.org/2000/svg', 'path')
          shaft.setAttribute('d', 'M7.8 8h6.6M11.6 8v2.6M14.4 8v2')
          svg.append(ring, shaft)
          button.append(svg)
          root.append(style, button)

          const set = (name, value) => host.style.setProperty(name, value, 'important')
          for (const [name, value] of [['position', 'fixed'], ['z-index', '2147483647'], ['margin', '0'], ['padding', '0'],
                                       ['border', '0'], ['display', 'none']]) set(name, value)

          const place = () => {
            if (!field || !field.isConnected || document.activeElement !== field) return hide()
            const r = field.getBoundingClientRect()
            // Fits inside the field: up to 22 pt, never under 12 pt.
            const size = Math.min(largest, r.height - 2 * inset)
            if (r.width < minimumWidth || size < smallest) return hide()
            set('width', size + 'px')
            set('height', size + 'px')
            set('left', (r.right - size - inset) + 'px')
            set('top', (r.top + (r.height - size) / 2) + 'px')
            if (!host.isConnected) document.documentElement.append(host)
            set('display', 'block')
          }
          const hide = () => { field = null; set('display', 'none') }

          document.addEventListener('focusin', async event => {
            const target = event.composedPath()[0]
            if (!isLoginField(target)) return hide()
            const request = ++requests
            const allowed = await handler.postMessage({ type: 'query' }).catch(() => false)
            if (!allowed || request !== requests || document.activeElement !== target) return
            field = target
            place()
          }, true)
          document.addEventListener('focusout', () => setTimeout(() => { if (document.activeElement !== field) hide() }), true)
          addEventListener('scroll', () => field && place(), { capture: true, passive: true })
          addEventListener('resize', () => field && place(), { passive: true })

          // Keep the field focused so Apple's panel fills it.
          button.addEventListener('mousedown', event => event.preventDefault())
          button.addEventListener('click', event => {
            event.preventDefault()
            event.stopPropagation()
            if (!event.isTrusted || !field) return
            requested = field
            field.focus()
            Promise.resolve(handler.postMessage({ type: 'fill' })).catch(() => {})
          })

          // Fills a login the person picked: visible, enabled fields of the form the key was in.
          const usable = el => visible(el) && !el.disabled && !el.readOnly
          const assign = (el, value) => {
            el.focus()
            Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(el, value)
            el.dispatchEvent(new Event('input', { bubbles: true }))
            el.dispatchEvent(new Event('change', { bubbles: true }))
          }
          // `origin` is the page the person unlocked the login for; a document that replaced it meanwhile gets nothing.
          const fill = (username, password, origin) => {
            if (location.origin !== origin) return false
            const target = requested && requested.isConnected ? requested : field
            if (!target) return false
            const scope = target.form || document
            const passwords = [...scope.querySelectorAll('input[type=password i]')].filter(usable)
            const pass = typeOf(target) === 'password' ? target : passwords[0] || null
            let user = typeOf(target) === 'password' ? null : target
            if (!user && pass) {
              user = textFields(scope).filter(el => usable(el) && (el.compareDocumentPosition(pass) & Node.DOCUMENT_POSITION_FOLLOWING)).pop() || null
            }
            if (user && username) assign(user, username)
            if (pass && password) assign(pass, password)
            ;(pass || user).focus()
            return true
          }

          window.__ikagoPasswordKey = {
            state: () => {
              const r = host.getBoundingClientRect()
              return { visible: host.style.getPropertyValue('display') === 'block', field: field ? field.id : null,
                       x: r.x + r.width / 2, y: r.y + r.height / 2 }
            },
            click: () => button.click(),
            // Whether a real click at this viewport point was on the visible key (Chromium).
            hit: (x, y) => {
              if (!field || host.style.getPropertyValue('display') !== 'block') return false
              const r = host.getBoundingClientRect()
              if (x < r.left || x > r.right || y < r.top || y > r.bottom) return false
              requested = field
              return true
            },
            fill
          }
        })()
        """
    }
}
