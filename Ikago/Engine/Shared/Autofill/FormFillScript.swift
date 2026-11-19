/// Address and card fields: the script that recognizes them, fills a saved address or card into a form, and notices a
/// submitted one worth saving. It runs in an isolated world, never the page's: WebKit's `.defaultClient` world in every
/// frame, or on Chromium the password world (the two scripts share it). Fields are recognized from their `autocomplete`
/// tokens first, then from their name, id, label and placeholder. The security code is never filled or saved.
enum FormFillScript {
    /// WebKit: the script tells native code about a focused field and a submit.
    static let source = make(transport: """
        const post = message => window.webkit.messageHandlers.\(FormAutoFill.handlerName).postMessage(message)
        """)

    /// Chromium: the script never sends anything; native code asks after real clicks, Tab and Return
    /// (`focusInfo`, `takeSubmitted`).
    static let chromium = make(transport: "const post = () => Promise.resolve(false)")

    private static func make(transport: String) -> String { """
        (() => {
          if (window.__ikagoFormFill) return
          \(transport)
          let lastInput = -Infinity, lastClick = false, focused = null, submitted = null

          const byToken = {
            'name': 'name', 'given-name': 'givenName', 'family-name': 'familyName', 'organization': 'organization',
            'street-address': 'street', 'address-line1': 'line1', 'address-line2': 'line2', 'address-level2': 'city',
            'address-level1': 'region', 'postal-code': 'postalCode', 'country': 'country', 'country-name': 'country',
            'email': 'email', 'tel': 'phone', 'tel-national': 'phone',
            'cc-name': 'cardName', 'cc-number': 'cardNumber', 'cc-exp': 'cardExpiry', 'cc-exp-month': 'cardExpMonth',
            'cc-exp-year': 'cardExpYear', 'cc-csc': 'cardCode'
          }
          // In order: the first that matches a field's name, id, label or placeholder wins.
          const byText = [
            ['cardCode', /cvc|cvv|csc|security.?code|card.?verification/i],
            ['cardNumber', /card.?(number|no\\b|num)|cc.?num|credit.?card|cardnumber/i],
            // One expiry field ("MM / YY", "exp-date") before a month or year field, which says so.
            ['cardExpiry', /mm\\s*\\/\\s*yy|exp\\w*.?date/i],
            // A month or year counts only beside "exp", "cc" or "card": a birthday's MM/DD/YYYY is never a card.
            ['cardExpMonth', /(exp|cc|card)\\w*.?(month|mm\\b)/i],
            ['cardExpYear', /(exp|cc|card)\\w*.?(year|yy)/i],
            ['cardExpiry', /expir/i],
            ['cardName', /(card|cc).?(holder|name)|name.?on.?card/i],
            ['email', /e.?mail/i],
            ['phone', /phone|mobile|\\btel\\b|telephone/i],
            ['postalCode', /zip|postal|post.?code|postcode/i],
            ['city', /\\bcity\\b|town|locality|suburb/i],
            ['region', /\\bstate\\b|province|region|county/i],
            ['country', /country/i],
            ['line2', /address.?(line)?.?2|\\bapt\\b|suite|apartment|\\bunit\\b/i],
            ['line1', /address.?(line)?.?1|street|address/i],
            ['organization', /company|organi[sz]ation|business/i],
            ['givenName', /first.?name|given.?name|fname/i],
            ['familyName', /last.?name|surname|family.?name|lname/i],
            ['name', /full.?name|your.?name|^name$|\\bname\\b/i]
          ]
          const skipped = new Set(['hidden', 'password', 'checkbox', 'radio', 'submit', 'button', 'reset', 'file', 'image',
                                   'search', 'range', 'color', 'date', 'time', 'datetime-local', 'month', 'week'])
          // A field the person can see: a real size, not transparent, hidden, clipped away, moved off the page or covered
          // by something else. Pages that hide extra fields (a phone or street behind a visible name) get nothing in them.
          const visible = el => {
            const r = el.getBoundingClientRect()
            if (r.width < 4 || r.height < 4) return false
            if (el.checkVisibility && !el.checkVisibility({ opacityProperty: true, visibilityProperty: true, contentVisibilityAuto: true })) return false
            if (r.right <= 0 || r.bottom + scrollY <= 0 || r.left >= Math.max(document.documentElement.scrollWidth, innerWidth)) return false
            for (let node = el; node && node !== document.body && node !== document.documentElement; node = node.parentElement || (node.getRootNode() && node.getRootNode().host)) {
              const s = getComputedStyle(node)
              if (Number(s.opacity) < 0.1) return false
              if (s.clipPath && s.clipPath !== 'none' && /inset\\(\\s*(50%|100%)|circle\\(\\s*0|polygon\\(\\s*0/.test(s.clipPath)) return false
              if (s.clip && s.clip !== 'auto' && /rect\\(\\s*0(px)?[ ,]+0(px)?[ ,]+0(px)?[ ,]+0(px)?\\s*\\)/.test(s.clip)) return false
              if (node !== el && (s.overflowX === 'hidden' || s.overflowY === 'hidden' || s.overflow === 'clip')) {
                const p = node.getBoundingClientRect()
                if (r.right <= p.left + 1 || r.left >= p.right - 1 || r.bottom <= p.top + 1 || r.top >= p.bottom - 1) return false
              }
            }
            // In view: a field something else is drawn over (and takes clicks) can't be seen either.
            if (r.top >= 0 && r.bottom <= innerHeight && r.left >= 0 && r.right <= innerWidth) {
              const root = el.getRootNode && el.getRootNode().elementFromPoint ? el.getRootNode() : document
              const top = root.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2)
              const labels = el.labels ? [...el.labels] : []
              if (top && top !== el && !el.contains(top) && !top.contains(el) && !labels.some(l => l.contains(top))) return false
            }
            return true
          }
          const textOf = el => {
            const label = el.labels && el.labels[0] ? el.labels[0].textContent : ''
            return [el.name, el.id, label, el.getAttribute('placeholder'), el.getAttribute('aria-label')].join(' ').replace(/\\s+/g, ' ')
          }
          const classify = el => {
            if (!(el instanceof HTMLInputElement || el instanceof HTMLSelectElement || el instanceof HTMLTextAreaElement)) return null
            if (el.disabled || el.readOnly) return null
            if (el instanceof HTMLInputElement && skipped.has((el.getAttribute('type') || '').toLowerCase())) return null
            const tokens = (el.getAttribute('autocomplete') || '').toLowerCase().split(/\\s+/)
            for (const token of tokens) if (byToken[token]) return byToken[token]
            if (tokens.some(t => t === 'username' || t === 'current-password' || t === 'new-password' || t === 'one-time-code')) return null
            const type = (el.getAttribute('type') || '').toLowerCase()
            if (type === 'email') return 'email'
            if (type === 'tel') return 'phone'
            const text = textOf(el)
            for (const [kind, pattern] of byText) if (pattern.test(text)) return kind
            return null
          }
          const isCard = kind => kind && kind.startsWith('card')
          const scopeOf = el => el.form || (el.closest && el.closest('form, [role=form], dialog, [role=dialog]')) || document
          // The fields of one kind (address or card) in the field's form, in page order.
          const fieldsIn = (scope, card) => [...scope.querySelectorAll('input, select, textarea')]
            .filter(el => visible(el)).map(el => ({ el, kind: classify(el) })).filter(f => f.kind && isCard(f.kind) === card)
          const rectOf = el => { const r = el.getBoundingClientRect(); return { x: r.left, y: r.top, width: r.width, height: r.height } }
          const deepActive = () => {
            let el = document.activeElement
            while (el && el.shadowRoot && el.shadowRoot.activeElement) el = el.shadowRoot.activeElement
            return el
          }

          // What a focused field offers: its kind, and the kinds around it (so a lone search box isn't an address form).
          const describe = el => {
            const kind = classify(el)
            if (!kind || kind === 'cardCode') return null
            const card = isCard(kind)
            const kinds = [...new Set(fieldsIn(scopeOf(el), card).map(f => f.kind))]
            // An address needs a second address field beside it; a card field is enough on its own.
            if (!card && kinds.length < 2) return null
            return Object.assign(rectOf(el), { kind: card ? 'card' : 'address', field: kind, kinds })
          }
          const report = target => {
            const info = describe(target)
            focused = info ? target : null
            if (!info) return
            const click = performance.now() - lastInput < 600 && lastClick
            Promise.resolve(post(Object.assign({ type: 'focus', click }, info))).catch(() => {})
          }
          document.addEventListener('mousedown', event => {
            if (!event.isTrusted) return
            lastInput = performance.now(); lastClick = true
            const target = event.composedPath()[0]
            setTimeout(() => { if (deepActive() === target) report(target) })
          }, true)
          document.addEventListener('keydown', event => {
            if (!event.isTrusted) return
            if (event.key === 'Tab') { lastInput = performance.now(); lastClick = false }
            if (event.key === 'Enter') capture(event.composedPath()[0])
          }, true)
          document.addEventListener('focusin', event => {
            if (performance.now() - lastInput < 600 && !lastClick) report(event.composedPath()[0])
          }, true)

          // Filling: a native control's value setter, then the input and change events frameworks listen for.
          const setValue = (el, value) => {
            if (el instanceof HTMLSelectElement) {
              const wanted = String(value).toLowerCase()
              const option = [...el.options].find(o => o.value.toLowerCase() === wanted || o.text.trim().toLowerCase() === wanted)
                || [...el.options].find(o => wanted.length > 2 && o.text.trim().toLowerCase().startsWith(wanted))
              if (!option) return false
              el.value = option.value
            } else {
              const proto = el instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype
              Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, value)
            }
            el.dispatchEvent(new Event('input', { bubbles: true }))
            el.dispatchEvent(new Event('change', { bubbles: true }))
            return true
          }
          // An expiry in the shape the field wants: a month and year select or field, or one MM/YY (MM/YYYY when it fits).
          const expiryValue = (el, kind, month, year) => {
            const mm = String(month).padStart(2, '0'), yyyy = String(year), yy = yyyy.slice(-2)
            if (kind === 'cardExpMonth') {
              if (el instanceof HTMLSelectElement && ![...el.options].some(o => o.value === mm || o.text.trim() === mm)) return String(month)
              return mm
            }
            if (kind === 'cardExpYear') {
              if (el instanceof HTMLSelectElement) return [...el.options].some(o => o.value === yyyy || o.text.trim() === yyyy) ? yyyy : yy
              return el.maxLength === 2 ? yy : yyyy
            }
            return el.maxLength >= 7 && /yyyy/i.test(textOf(el)) ? mm + '/' + yyyy : mm + '/' + yy
          }
          // `values` by field kind; `origin` is the page it was chosen for. Never the security code.
          const fill = (values, card, origin) => {
            if (location.origin !== origin) return 0
            const target = focused && focused.isConnected ? focused : deepActive()
            if (!target) return 0
            let count = 0
            for (const { el, kind } of fieldsIn(scopeOf(target), !!card)) {
              if (kind === 'cardCode') continue
              let value = values[kind]
              if (kind === 'cardExpiry' || kind === 'cardExpMonth' || kind === 'cardExpYear') {
                if (!values.expMonth) continue
                value = expiryValue(el, kind, values.expMonth, values.expYear)
              }
              if (kind === 'street' && el instanceof HTMLInputElement) value = values.line1
              if (value && setValue(el, value)) count++
            }
            if (target.isConnected) target.focus()
            return count
          }

          // Saving: on a submit, Return or a button, what the form holds; native code offers to save it.
          const capture = from => {
            const scope = scopeOf(from instanceof Element ? from : document.body)
            const read = card => {
              const out = {}
              for (const { el, kind } of fieldsIn(scope, card)) {
                if (kind === 'cardCode') continue
                const value = el instanceof HTMLSelectElement ? (el.selectedOptions[0] ? el.selectedOptions[0].text.trim() : '') : el.value.trim()
                if (value && !out[kind]) out[kind] = kind === 'cardExpMonth' || kind === 'cardExpYear' ? (el.value || value) : value
              }
              return out
            }
            const address = read(false), card = read(true)
            const hasAddress = (address.line1 || address.street) && (address.postalCode || address.city)
            const hasCard = card.cardNumber && card.cardNumber.replace(/\\D/g, '').length >= 12
            if (!hasAddress && !hasCard) return
            submitted = { address: hasAddress ? address : null, card: hasCard ? card : null, at: Date.now() }
            Promise.resolve(post({ type: 'submitted', address: submitted.address, card: submitted.card })).catch(() => {})
          }
          document.addEventListener('submit', event => capture(event.target), true)
          document.addEventListener('click', event => {
            if (!event.isTrusted) return
            const target = event.composedPath()[0]
            const control = target && target.closest && target.closest('button, input[type=submit i], [role=button]')
            if (control) capture(control)
          }, true)

          window.__ikagoFormFill = {
            fill,
            classify: el => classify(el),
            // Chromium: the focused field after a real click or Tab, if it is an address or card field.
            focusInfo: () => { const el = deepActive(); const info = el && describe(el); focused = info ? el : null; return info || null },
            // Chromium: a submitted address or card, handed over once.
            takeSubmitted: () => {
              if (!submitted || Date.now() - submitted.at > 20000) return null
              const value = submitted
              submitted = null
              return value
            }
          }
        })()
        """
    }
}
