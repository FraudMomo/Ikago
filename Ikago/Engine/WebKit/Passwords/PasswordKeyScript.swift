/// The key button Ikago shows in sign-in fields, and the watcher that notices a sign-in worth saving. It runs in an
/// isolated world, never the page's: WebKit's `.defaultClient` world in every frame, or on Chromium the
/// "ikago-passwords" world of the main frame and same-site frames (a sign-in iframe such as Apple's). Native code decides whether a frame may show it, and only a trusted click asks
/// native code to fill: Apple's panel, or a login from Ikago's vault after Touch ID, which native code
/// passes to `fill`. The DOM is built without innerHTML so pages that require Trusted Types keep working.
enum PasswordKeyScript {
    /// WebKit: replies come back through the message handler's promise.
    static let source = make(transport: """
        let keyAllowed = true
        const post = message => window.webkit.messageHandlers.\(PasswordAutoFill.handlerName).postMessage(message)
        """)

    /// Chromium: native code says whether the key may show (`setKeyAllowed`). The script never sends anything:
    /// native code sees real clicks and keys and then asks the script (`hit`, `focusRect`, `poll`).
    static let chromium = make(transport: "let keyAllowed = false\nconst post = message => Promise.resolve(message.type === 'query' ? keyAllowed : false)")

    private static func make(transport: String) -> String { """
        (() => {
          if (window.__ikagoPasswordKey) return
          \(transport)
          const handler = { postMessage: post }
          const largest = 22, smallest = 12, inset = 3, minimumWidth = 80
          const textTypes = new Set(['', 'text', 'email', 'tel'])
          const userPattern = /user|log-?in|e-?mail|account|identifier|sign-?in|phone|handle/i
          let field = null, requested = null, requests = 0, lastInput = -Infinity, lastClick = false, keyClickedAt = 0

          // The focused element, inside open shadow roots too (web components keep their inputs there).
          const deepActive = () => {
            let el = document.activeElement
            while (el && el.shadowRoot && el.shadowRoot.activeElement) el = el.shadowRoot.activeElement
            return el
          }
          // Walks up through shadow roots, so a field in a component inside a modal dialog still finds the dialog.
          const parentOf = el => el.parentElement || (el.getRootNode && el.getRootNode().host) || null
          // A modal dialog or open popover sits in the top layer, above any z-index; the key joins it there.
          const inTopLayer = el => {
            for (let node = el; node; node = parentOf(node)) {
              try { if (node.matches(':modal, :popover-open')) return true } catch { return false }
            }
            return false
          }

          const rectOf = el => { const r = el.getBoundingClientRect(); return { x: r.left, y: r.top, width: r.width, height: r.height } }
          // Asks native code to list logins under the field (WebKit); Chromium reads `focusRect` instead.
          const suggest = () => {
            if (!field) return
            requested = field
            // A click puts the pointer on the field, so a frame without a known offset can list there; Tab can't.
            const click = performance.now() - lastInput < 600 && lastClick
            Promise.resolve(handler.postMessage({ type: 'suggest', rect: rectOf(field), click })).catch(() => {})
          }
          const typeOf = el => (el.getAttribute('type') || '').toLowerCase()
          const scopeOf = el => el.form || (el.closest && el.closest('form, dialog, [role=dialog]')) || el.getRootNode() || document
          const tokens = el => (el.getAttribute('autocomplete') || '').toLowerCase().split(/\\s+/)
          const visible = el => { const r = el.getBoundingClientRect(); return r.width > 0 && r.height > 0 }
          const textFields = scope => [...scope.querySelectorAll('input')]
            .filter(el => textTypes.has(typeOf(el)) && visible(el))
          // Passwords, annotated usernames, and username-like fields (by name, label or placeholder) in a password form
          // or a short "enter your email" step.
          const isLoginField = el => {
            if (!(el instanceof HTMLInputElement) || el.disabled || el.readOnly) return false
            const type = typeOf(el)
            if (type === 'password') return true
            if (!textTypes.has(type)) return false
            if (tokens(el).some(t => t === 'username' || t === 'webauthn')) return true
            const identity = [el.name, el.id, el.getAttribute('autocomplete'), el.getAttribute('placeholder'),
                              el.getAttribute('aria-label'), type === 'email' ? 'email' : ''].join(' ')
            if (!userPattern.test(identity)) return false
            const scope = scopeOf(el)
            if (scope.querySelector('input[type=password i]')) return true
            return el.form ? textFields(scope).length <= 2 : textFields(scope).length === 1
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
                                       ['border', '0'], ['inset', 'auto'], ['overflow', 'visible'], ['background', 'transparent'],
                                       ['display', 'none']]) set(name, value)
          const popovers = typeof host.showPopover === 'function'
          if (popovers) host.setAttribute('popover', 'manual')
          // Shown again on top of the field's dialog, or taken out of the top layer when the field isn't in one.
          const raise = () => {
            if (!popovers) return
            const wanted = inTopLayer(field)
            try {
              if (host.matches(':popover-open')) host.hidePopover()
              if (wanted) host.showPopover()
            } catch {}
          }

          const place = () => {
            if (!field || !field.isConnected || deepActive() !== field) return hide()
            const r = field.getBoundingClientRect()
            // Fits inside the field: up to 22 pt, never under 12 pt.
            const size = Math.min(largest, r.height - 2 * inset)
            // Too small for now (a dialog still growing in): out of sight, but still this field's key.
            if (r.width < minimumWidth || size < smallest) return conceal()
            set('width', size + 'px')
            set('height', size + 'px')
            set('left', (r.right - size - inset) + 'px')
            set('top', (r.top + (r.height - size) / 2) + 'px')
            if (!host.isConnected) document.documentElement.append(host)
            set('display', 'block')
          }
          const conceal = () => set('display', 'none')
          const hide = () => {
            field = null
            conceal()
            if (popovers && host.matches(':popover-open')) try { host.hidePopover() } catch {}
          }

          // Shows the key in a focused sign-in field. A field the page makes writable on focus is looked at again.
          const attach = async target => {
            if (!isLoginField(target)) {
              if (target instanceof HTMLInputElement && target.readOnly && !target.disabled) {
                setTimeout(() => { if (deepActive() === target && !target.readOnly) attach(target) }, 250)
              }
              return hide()
            }
            const request = ++requests
            const allowed = await Promise.resolve(handler.postMessage({ type: 'query' })).catch(() => false)
            if (!allowed || request !== requests || deepActive() !== target) return
            field = target
            place()
            raise()
            if (performance.now() - lastInput < 600) suggest()
            // A field focused while its dialog animates in moves and grows; measure again as it settles.
            for (const delay of [120, 350, 800]) setTimeout(() => { if (field === target) { place(); raise() } }, delay)
          }
          document.addEventListener('focusin', event => attach(event.composedPath()[0]), true)
          // Only the person's own click or Tab opens the list; a page focusing a field by itself doesn't. A click in a
          // field that was focused before this script ran (autofocus) shows the key then.
          document.addEventListener('mousedown', event => {
            if (!event.isTrusted) return
            lastInput = performance.now()
            lastClick = true
            const target = event.composedPath()[0], known = !!field && target === field
            setTimeout(() => {
              if (known) { place(); raise(); return suggest() }
              if (target !== field && deepActive() === target) attach(target)
            })
          }, true)
          document.addEventListener('keydown', event => {
            if (event.isTrusted && event.key === 'Tab') { lastInput = performance.now(); lastClick = false }
          }, true)
          document.addEventListener('focusout', () => setTimeout(() => { if (deepActive() !== field) hide() }), true)
          addEventListener('scroll', () => field && place(), { capture: true, passive: true })
          addEventListener('resize', () => field && place(), { passive: true })

          // Keep the field focused so Apple's panel fills it.
          button.addEventListener('mousedown', event => event.preventDefault())
          button.addEventListener('click', event => {
            event.preventDefault()
            event.stopPropagation()
            if (!event.isTrusted || !field) return
            requested = field
            keyClickedAt = Date.now()
            field.focus()
            Promise.resolve(handler.postMessage({ type: 'fill', rect: rectOf(field) })).catch(() => {})
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

          // Saving: a sign-in is a filled password sent by a form submit, Return, or a button. It's confirmed once the
          // password field goes away or the page moves on (a rejected password leaves the field), then offered.
          let lastUser = '', pending = null, watch = null
          const confirm = () => {
            if (!pending || pending.confirmed) return
            pending.confirmed = true
            clearInterval(watch)
            Promise.resolve(handler.postMessage({ type: 'save', username: pending.username, password: pending.password,
                                                  leaving: pending.leaving })).catch(() => {})
          }
          const capture = from => {
            const scope = (from && from.closest && from.closest('form')) || document
            const passwords = [...scope.querySelectorAll('input[type=password i]')].filter(el => el.value && !el.disabled)
            if (!passwords.length) return
            // Sign-up and change forms repeat the new password; the last field holds it.
            const pass = passwords[passwords.length - 1]
            const before = textFields(scope).filter(el => el.value && (el.compareDocumentPosition(pass) & Node.DOCUMENT_POSITION_FOLLOWING))
            const named = before.filter(isLoginField).pop() || before.pop()
            const username = (named ? named.value : lastUser).trim()
            if (pending && !pending.confirmed && pending.password === pass.value && pending.username === username) return
            pending = { username, password: pass.value, field: pass, href: location.href, at: Date.now(), confirmed: false, leaving: false }
            clearInterval(watch)
            watch = setInterval(() => {
              if (!pending || Date.now() - pending.at > 20000) return clearInterval(watch)
              const f = pending.field
              if (!f.isConnected || !visible(f) || location.href !== pending.href) confirm()
            }, 400)
          }
          document.addEventListener('submit', event => capture(event.target), true)
          document.addEventListener('keydown', event => {
            if (!event.isTrusted || event.key !== 'Enter') return
            const target = event.composedPath()[0]
            if (target instanceof HTMLInputElement) capture(target)
          }, true)
          document.addEventListener('click', event => {
            if (!event.isTrusted) return
            const target = event.composedPath()[0]
            const control = target && target.closest && target.closest('button, input[type=submit i], input[type=image i], [role=button]')
            if (control && !host.contains(control)) capture(control)
          }, true)
          // Two-step sign-ins ask for the username first, so remember it.
          document.addEventListener('input', event => {
            const target = event.composedPath()[0]
            if (event.isTrusted && target instanceof HTMLInputElement && typeOf(target) !== 'password' && isLoginField(target)) lastUser = target.value
          }, true)
          addEventListener('pagehide', () => {
            if (pending && !pending.confirmed && Date.now() - pending.at < 20000) { pending.leaving = true; confirm() }
          })

          window.__ikagoPasswordKey = {
            state: () => {
              const r = host.getBoundingClientRect()
              return { visible: host.style.getPropertyValue('display') === 'block', field: field ? field.id : null,
                       covered: !!field && inTopLayer(field) && !(popovers && host.matches(':popover-open')),
                       x: r.x + r.width / 2, y: r.y + r.height / 2 }
            },
            click: () => button.click(),
            // Whether a real click at this viewport point was on the visible key (Chromium).
            hit: (x, y) => {
              if (!field || host.style.getPropertyValue('display') !== 'block') return false
              const r = host.getBoundingClientRect()
              if (x < r.left || x > r.right || y < r.top || y > r.bottom) return false
              requested = field
              return rectOf(field)
            },
            // The focused sign-in field after a real click or Tab (Chromium), so native code can list logins under it.
            focusRect: () => {
              if (!field || deepActive() !== field || host.style.getPropertyValue('display') !== 'block') return null
              requested = field
              return rectOf(field)
            },
            setKeyAllowed: allowed => { keyAllowed = !!allowed; if (!allowed) hide() },
            // Chromium: whether the key was clicked since native code last asked, as the field's rect in this frame.
            poll: () => {
              const result = {}
              if (field && Date.now() - keyClickedAt < 1500) { keyClickedAt = 0; requested = field; result.key = rectOf(field) }
              return result
            },
            // Chromium: the sign-in waiting to be saved, confirmed or not; a confirmed one is handed over only once.
            saveState: () => {
              if (!pending || Date.now() - pending.at > 20000) return null
              const state = { username: pending.username, password: pending.password, confirmed: pending.confirmed }
              if (pending.confirmed) pending = null
              return state
            },
            // A new page that still asks for a password means the sign-in didn't go through.
            hasPasswordField: () => [...document.querySelectorAll('input[type=password i]')].some(visible),
            fill
          }
          // A field focused before this script ran (autofocus) gets the key right away.
          const focused = deepActive()
          if (focused instanceof HTMLInputElement) attach(focused)
        })()
        """
    }
}
