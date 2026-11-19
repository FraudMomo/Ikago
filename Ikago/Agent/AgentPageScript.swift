/// The page side of agent access: a compact, ref-addressed outline of a page for a language model, and the actions it
/// can take there. It runs in Ikago's isolated world (the page can't see or change it) and installs itself on first use
/// in each document (`AgentPage`).
///
/// - **Stable refs.** Every element the outline mentions gets an id (`e12`) kept in a WeakMap for the document's life,
///   so a ref stays valid across outlines until its element goes away; a stale ref is reported, never guessed.
/// - **Outline, not dump.** Landmarks, headings, controls with their state, and short visible text, one line each, in
///   reading order, nested by landmark. By default only around the viewport, with counts of what is above and below;
///   long lists and tables collapse to their first rows and a ref to expand.
/// - **Changes after actions.** Each action returns what changed since the last outline (lines added, removed or
///   changed, the URL and title, the focused field), not a new outline.
/// - **Text on demand** for one part of the page, and **find** by words.
enum AgentPageScript {
    static let install = #"""
    if (!window.__ikagoAgent) (() => {
      const refs = new Map(), ids = new WeakMap()
      let next = 1, last = null, lastOptions = {}
      const refOf = el => { let id = ids.get(el); if (!id) { id = 'e' + next++; ids.set(el, id); refs.set(id, new WeakRef(el)) } return id }
      const byRef = id => { const r = refs.get(id), el = r && r.deref(); return el && el.isConnected ? el : null }
      const clip = (text, n) => { text = (text || '').replace(/\s+/g, ' ').trim(); return text.length > n ? text.slice(0, n - 1) + '…' : text }
      const quote = text => '"' + text.replace(/"/g, '\\"') + '"'

      const boxOf = el => {
        const r = el.getBoundingClientRect()
        if (r.width < 1 || r.height < 1) return null
        const s = getComputedStyle(el)
        if (s.visibility === 'hidden' || s.visibility === 'collapse' || Number(s.opacity) === 0) return null
        return r
      }
      const hiddenTree = el => {
        if (el.hidden || el.getAttribute('aria-hidden') === 'true' || el.inert) return true
        const s = getComputedStyle(el)
        return s.display === 'none' || s.contentVisibility === 'hidden'
      }

      const inputRoles = { checkbox: 'checkbox', radio: 'radio', range: 'slider', submit: 'button', button: 'button', reset: 'button',
                           image: 'button', search: 'searchbox', email: 'textbox', tel: 'textbox', url: 'textbox', number: 'spinbutton',
                           password: 'password', file: 'file', date: 'date', time: 'time', 'datetime-local': 'date', month: 'date', color: 'color' }
      const roleOf = el => {
        const explicit = (el.getAttribute('role') || '').split(' ')[0]
        if (explicit) return explicit
        const tag = el.tagName
        if (tag === 'A' && el.hasAttribute('href')) return 'link'
        if (tag === 'BUTTON' || tag === 'SUMMARY') return 'button'
        if (tag === 'INPUT') return inputRoles[(el.type || '').toLowerCase()] || 'textbox'
        if (tag === 'TEXTAREA') return 'textbox'
        if (tag === 'SELECT') return 'select'
        if (/^H[1-6]$/.test(tag)) return 'heading'
        if (el.isContentEditable && el === el.closest('[contenteditable]')) return 'textbox'
        const landmark = { HEADER: 'banner', NAV: 'navigation', MAIN: 'main', ASIDE: 'complementary', FOOTER: 'contentinfo',
                           FORM: 'form', DIALOG: 'dialog', TABLE: 'table', UL: 'list', OL: 'list', IMG: 'img' }[tag]
        return landmark || ''
      }
      const controls = new Set(['link', 'button', 'checkbox', 'radio', 'slider', 'searchbox', 'textbox', 'spinbutton', 'password',
        'file', 'date', 'time', 'color', 'select', 'combobox', 'listbox', 'option', 'menuitem', 'menuitemcheckbox', 'menuitemradio',
        'tab', 'switch', 'treeitem'])
      const sections = new Set(['banner', 'navigation', 'main', 'complementary', 'contentinfo', 'form', 'dialog', 'alertdialog',
        'region', 'search', 'tabpanel', 'menu', 'toolbar', 'tablist'])
      const isControl = (el, role) => controls.has(role) ||
        (el.tabIndex >= 0 && !['BODY', 'HTML', 'IFRAME'].includes(el.tagName) && (el.hasAttribute('onclick') || getComputedStyle(el).cursor === 'pointer'))

      const labelled = el => {
        const by = el.getAttribute('aria-labelledby')
        if (by) return by.split(/\s+/).map(id => { const t = document.getElementById(id); return t ? t.textContent : '' }).join(' ')
        return ''
      }
      // A label's own words, without the text of the controls inside it (a select's options).
      const labelText = el => {
        const label = el.labels && el.labels[0]
        if (!label) return ''
        const copy = label.cloneNode(true)
        for (const control of copy.querySelectorAll('input, select, textarea, button')) control.remove()
        return copy.textContent
      }
      // A section is named only by what names it on purpose, never by all the text inside it.
      const sectionName = el => clip(el.getAttribute('aria-label') || labelled(el) || el.getAttribute('title') || '', 50)
      const nameOf = el => clip(el.getAttribute('aria-label') || labelled(el) || labelText(el) ||
        el.getAttribute('alt') || (el.tagName === 'INPUT' && ['submit', 'button', 'reset'].includes(el.type) ? el.value : '') ||
        el.getAttribute('title') || el.getAttribute('placeholder') || el.innerText || el.textContent || '', 80)

      // Fields an agent never types into or reads: passwords and card numbers or codes (the person fills those), and
      // one-time codes, whose value stays hidden. By type, autocomplete token, then name, id, label or placeholder.
      const sensitiveOf = el => {
        if (!(el instanceof HTMLInputElement || el instanceof HTMLTextAreaElement)) return null
        const tokens = (el.getAttribute('autocomplete') || '').toLowerCase().split(/\s+/)
        if ((el.type || '').toLowerCase() === 'password' || tokens.includes('current-password') || tokens.includes('new-password')) return 'password'
        if (tokens.includes('cc-number') || tokens.includes('cc-csc')) return 'card'
        if (tokens.includes('one-time-code')) return 'code'
        const text = [el.name, el.id, el.getAttribute('placeholder'), el.getAttribute('aria-label'), labelText(el)].join(' ')
        if (/cvc|cvv|csc|security.?code|card.?(number|no\b|num)|cc.?num|credit.?card|cardnumber/i.test(text)) return 'card'
        return null
      }

      // One line per control, with what an agent needs to act on it.
      const describe = (el, role) => {
        const parts = ['[' + refOf(el) + ']', role === '' ? 'clickable' : role]
        const name = nameOf(el)
        if (name) parts.push(quote(name))
        if (role === 'link') { const href = el.getAttribute('href') || ''; if (href && !href.startsWith('javascript:')) parts.push('→ ' + clip(href, 60)) }
        if (role === 'checkbox' || role === 'radio' || role === 'switch') parts.push(el.checked || el.getAttribute('aria-checked') === 'true' ? '✓' : '☐')
        if (role === 'select') {
          const chosen = el.selectedOptions && el.selectedOptions[0]
          parts.push('= ' + quote(chosen ? clip(chosen.text, 40) : ''), '(' + el.options.length + ' options)')
        } else if (['textbox', 'searchbox', 'spinbutton', 'date', 'time', 'combobox'].includes(role)) {
          const value = el.isContentEditable ? el.innerText : el.value
          const sensitive = sensitiveOf(el)
          if (sensitive) parts.push(value ? '(filled; hidden from agents)' : sensitive === 'card' ? '(the person fills this)' : '(hidden from agents)')
          else if (value) parts.push('= ' + quote(clip(value, 60)))
        } else if (role === 'password') parts.push('(Ikago never types passwords)')
        if (el.required || el.getAttribute('aria-required') === 'true') parts.push('(required)')
        if (el.disabled || el.getAttribute('aria-disabled') === 'true') parts.push('(disabled)')
        if (el.getAttribute('aria-expanded')) parts.push(el.getAttribute('aria-expanded') === 'true' ? '(expanded)' : '(collapsed)')
        if (el.getAttribute('aria-selected') === 'true' || el.getAttribute('aria-current')) parts.push('(current)')
        return parts.join(' ')
      }

      // Own text of an element that holds no controls or blocks: a paragraph, a cell, a price.
      const blocks = new Set(['P', 'LI', 'TD', 'TH', 'DT', 'DD', 'BLOCKQUOTE', 'FIGCAPTION', 'LABEL', 'SPAN', 'DIV', 'STRONG', 'EM', 'PRE', 'CODE', 'TIME'])
      const leafText = el => {
        if (!blocks.has(el.tagName)) return ''
        for (const child of el.children) {
          if (controls.has(roleOf(child)) || /^(P|DIV|UL|OL|TABLE|SECTION|ARTICLE|H[1-6])$/.test(child.tagName)) return ''
        }
        return clip(el.innerText, 120)
      }

      const near = (r, o) => o.all || (r.bottom > -o.margin && r.top < innerHeight + o.margin)
      const walk = (root, depth, out, o, stats) => {
        const kids = root.shadowRoot ? [...root.shadowRoot.children, ...root.children] : [...root.children]
        let shown = 0
        for (const el of kids) {
          if (out.length >= o.limit) { stats.cut++; continue }
          if (['SCRIPT', 'STYLE', 'NOSCRIPT', 'TEMPLATE', 'SVG', 'svg', 'HEAD', 'META', 'LINK'].includes(el.tagName)) continue
          if (hiddenTree(el)) continue
          // Long lists and tables: their first rows, then a ref to see the rest.
          if (root.children.length > o.listCap + 4 && shown >= o.listCap && ['UL', 'OL', 'TBODY', 'TABLE', 'DIV'].includes(root.tagName)) {
            out.push('  '.repeat(depth) + '… ' + (kids.length - shown) + ' more [' + refOf(root) + ']')
            break
          }
          const role = roleOf(el), box = boxOf(el)
          const indent = '  '.repeat(depth)
          if (role === 'heading' && box) {
            if (near(box, o)) { out.push(indent + 'heading' + el.tagName[1] + ' ' + quote(clip(el.innerText, 100))); shown++ }
            else if (box.top < 0) stats.above++; else stats.below++
            continue
          }
          if (role !== '' && isControl(el, role) || (role === '' && box && isControl(el, role) && !el.querySelector('a, button, input, select, textarea'))) {
            if (!box) continue
            if (near(box, o)) { out.push(indent + describe(el, role)); shown++ } else if (box.top < 0) stats.above++; else stats.below++
            if (role !== 'select') walk(el, depth + 1, out, o, stats)
            continue
          }
          if (sections.has(role) || (role === 'list' && el.children.length > 0) || role === 'table') {
            const name = sectionName(el)
            const before = out.length
            out.push(indent + role + (name ? ' ' + quote(name) : ''))
            walk(el, depth + 1, out, o, stats)
            if (out.length === before + 1) out.pop()  // nothing near the viewport inside it
            continue
          }
          if (role === 'img' && box && near(box, o) && el.getAttribute('alt')) { out.push(indent + 'img ' + quote(clip(el.getAttribute('alt'), 60))); continue }
          if (el.tagName === 'IFRAME' && box && near(box, o)) { out.push(indent + '[' + refOf(el) + '] frame ' + quote(clip(el.title || el.src, 60))); continue }
          if (el.tagName === 'CANVAS' && box && near(box, o) && box.width > 100) { out.push(indent + '[' + refOf(el) + '] canvas (ask for a screenshot to see it)'); continue }
          const text = o.text && box ? leafText(el) : ''
          if (text) { if (near(box, o)) { out.push(indent + 'text ' + quote(text)); shown++ } continue }
          walk(el, depth, out, o, stats)
        }
      }

      const outline = (options = {}) => {
        const o = { all: !!options.all, text: options.text !== false, limit: options.limit || 400, listCap: 8, margin: innerHeight * 0.5 }
        if (!options.ref) lastOptions = options
        const root = options.ref ? byRef(options.ref) : document.body
        if (!root) return { error: 'No element ' + options.ref + ' on the page now; get a new outline.' }
        // One part asked for by ref: all of it, its long lists too.
        if (options.ref) { o.all = true; o.listCap = Infinity }
        const out = [], stats = { above: 0, below: 0, cut: 0 }
        walk(root, 0, out, o, stats)
        const lines = new Map(), texts = new Set()
        for (const line of out) {
          const m = line.match(/^\s*\[(e\d+)\]/)
          if (m) lines.set(m[1], line.trim()); else if (!line.trim().startsWith('…')) texts.add(line.trim())
        }
        if (!options.ref) last = { lines, texts, url: location.href, title: document.title, focus: document.activeElement }
        const head = [document.title + ' — ' + location.href,
          'viewport ' + Math.round(scrollY) + '–' + Math.round(scrollY + innerHeight) + ' of ' + document.documentElement.scrollHeight + 'px']
        if (stats.above || stats.below) head.push((stats.above ? stats.above + ' more above' : '') + (stats.above && stats.below ? ', ' : '') +
          (stats.below ? stats.below + ' more below' : '') + ' (scroll, or outline with all)')
        if (stats.cut) head.push(stats.cut + ' more not shown (outline a ref for one part)')
        return { text: head.join('\n') + '\n\n' + out.join('\n') }
      }

      // What changed since the last outline: added, removed and changed controls, and the page itself.
      const changes = () => {
        if (!last) return outline(lastOptions).text
        const before = last, notes = []
        outline(lastOptions)
        if (location.href !== before.url) notes.push('url: ' + location.href)
        if (document.title !== before.title) notes.push('title: ' + document.title)
        const added = [], removed = [], changed = []
        for (const [ref, line] of last.lines) {
          const old = before.lines.get(ref)
          if (old === undefined) added.push('+ ' + line); else if (old !== line) changed.push('~ ' + line)
        }
        for (const [ref, line] of before.lines) if (!last.lines.has(ref)) removed.push('- ' + line)
        // Text that appeared or went away: a message, a price, an error under a field.
        for (const line of last.texts) if (!before.texts.has(line) && !/^(banner|navigation|main|form|list|table|contentinfo|complementary|region)/.test(line)) added.push('+ ' + line)
        for (const line of before.texts) if (!last.texts.has(line) && !/^(banner|navigation|main|form|list|table|contentinfo|complementary|region)/.test(line)) removed.push('- ' + line)
        if (document.activeElement && document.activeElement !== before.focus && document.activeElement !== document.body) {
          notes.push('focus: [' + refOf(document.activeElement) + '] ' + nameOf(document.activeElement))
        }
        const diff = [...changed, ...added.slice(0, 40), ...(added.length > 40 ? ['+ … ' + (added.length - 40) + ' more'] : []),
                      ...removed.slice(0, 20), ...(removed.length > 20 ? ['- … ' + (removed.length - 20) + ' more'] : [])]
        if (!notes.length && !diff.length) return 'No visible change.'
        return [...notes, ...diff].join('\n')
      }

      const text = ({ ref, max = 4000 } = {}) => {
        const el = ref ? byRef(ref) : (document.querySelector('main, article, [role=main]') || document.body)
        if (!el) return 'No element ' + ref + ' on the page now.'
        const all = (el.innerText || '').replace(/\n{3,}/g, '\n\n').trim()
        return all.length > max ? all.slice(0, max) + '\n… ' + (all.length - max) + ' more characters (ask with a larger max)' : all
      }

      const find = ({ query }) => {
        const words = String(query || '').toLowerCase().split(/\s+/).filter(Boolean)
        const found = []
        for (const el of document.querySelectorAll('a, button, input, select, textarea, [role], h1, h2, h3, h4, label, [tabindex], [onclick]')) {
          if (found.length >= 20) break
          const box = boxOf(el)
          if (!box || hiddenTree(el)) continue
          const hay = (nameOf(el) + ' ' + (el.getAttribute('href') || '')).toLowerCase()
          if (words.every(w => hay.includes(w))) found.push(describe(el, roleOf(el) || 'clickable') + (box.top < 0 || box.top > innerHeight ? ' (off screen)' : ''))
        }
        return found.length ? found.join('\n') : 'Nothing on the page matches ' + quote(String(query))
      }

      // Where an element is, scrolled into view, and whether something covers it.
      const point = ({ ref }) => {
        const el = byRef(ref)
        if (!el) return { error: 'No element ' + ref + ' on the page now; get a new outline.' }
        el.scrollIntoView({ block: 'center', inline: 'center', behavior: 'instant' })
        const r = el.getBoundingClientRect()
        const x = r.left + Math.min(r.width / 2, Math.max(1, r.width - 2)), y = r.top + r.height / 2
        const top = document.elementFromPoint(x, y)
        const covered = top && top !== el && !el.contains(top) && !top.contains(el) ? nameOf(top) || top.tagName.toLowerCase() : null
        return { x, y, width: r.width, height: r.height, role: roleOf(el) || 'clickable', name: nameOf(el), covered,
                 sensitive: sensitiveOf(el), disabled: !!el.disabled }
      }

      // The person sees where the agent acts: a ring and a label over the element, fading after a moment.
      let marker = null
      const highlight = ({ ref, label }) => {
        const el = byRef(ref)
        if (!el) return false
        const r = el.getBoundingClientRect()
        if (!marker) {
          marker = document.createElement('ikago-agent-mark')
          const root = marker.attachShadow({ mode: 'closed' })
          const style = document.createElement('style')
          style.textContent = `:host { all: initial; position: fixed; z-index: 2147483647; pointer-events: none; inset: 0 }
            .ring { position: fixed; border: 2px solid #8b5cf6; border-radius: 8px; box-shadow: 0 0 0 4px rgba(139,92,246,.25);
                    transition: all .25s cubic-bezier(.2,.8,.2,1) }
            .tag { position: fixed; font: 600 11px -apple-system, sans-serif; color: #fff; background: #8b5cf6; padding: 3px 7px;
                   border-radius: 6px; white-space: nowrap; transition: all .25s cubic-bezier(.2,.8,.2,1) }`
          const ring = document.createElement('div'); ring.className = 'ring'
          const tag = document.createElement('div'); tag.className = 'tag'
          root.append(style, ring, tag)
          marker.parts = { ring, tag }
        }
        if (!marker.isConnected) document.documentElement.append(marker)
        const { ring, tag } = marker.parts
        Object.assign(ring.style, { left: r.left - 4 + 'px', top: r.top - 4 + 'px', width: r.width + 8 + 'px', height: r.height + 8 + 'px', opacity: '1' })
        tag.textContent = label || 'Agent'
        Object.assign(tag.style, { left: Math.max(4, r.left - 4) + 'px', top: Math.max(4, r.top - 26) + 'px', opacity: '1' })
        clearTimeout(marker.fade)
        marker.fade = setTimeout(() => { ring.style.opacity = '0'; tag.style.opacity = '0' }, 1400)
        return true
      }

      // Actions in the page's own terms (WebKit; Chromium sends real input instead where it can).
      const fire = (el, type, init = {}) => el.dispatchEvent(new (type.startsWith('pointer') ? PointerEvent : MouseEvent)(type,
        Object.assign({ bubbles: true, cancelable: true, composed: true, view: window }, init)))
      const click = ({ ref }) => {
        const p = point({ ref })
        if (p.error) return p
        const el = byRef(ref), at = { clientX: p.x, clientY: p.y, button: 0 }
        for (const type of ['pointerover', 'pointerenter', 'mouseover', 'pointerdown', 'mousedown']) fire(el, type, at)
        if (el.focus) el.focus({ preventScroll: true })
        for (const type of ['pointerup', 'mouseup']) fire(el, type, at)
        el.click()
        return { ok: true }
      }
      const setText = (el, value) => {
        if (el.isContentEditable) { el.focus(); document.execCommand('selectAll'); document.execCommand('insertText', false, value); return }
        const proto = el instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype
        Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, value)
        el.dispatchEvent(new InputEvent('input', { bubbles: true, composed: true, inputType: 'insertText', data: value }))
        el.dispatchEvent(new Event('change', { bubbles: true }))
      }
      const key = (el, name) => {
        for (const type of ['keydown', 'keypress', 'keyup']) {
          el.dispatchEvent(new KeyboardEvent(type, { key: name, code: name === 'Enter' ? 'Enter' : name, bubbles: true, cancelable: true, composed: true }))
        }
      }
      const type = ({ ref, text, append, submit }) => {
        const el = byRef(ref)
        if (!el) return { error: 'No element ' + ref + ' on the page now; get a new outline.' }
        const sensitive = sensitiveOf(el)
        if (sensitive === 'password' || sensitive === 'card') return { error: refusal(sensitive) }
        el.scrollIntoView({ block: 'center', behavior: 'instant' })
        el.focus()
        setText(el, append ? (el.value || '') + text : text)
        if (submit) { key(el, 'Enter'); if (el.form) el.form.requestSubmit() }
        return { ok: true }
      }
      const select = ({ ref, value }) => {
        const el = byRef(ref)
        if (!el) return { error: 'No element ' + ref + ' on the page now; get a new outline.' }
        if (!(el instanceof HTMLSelectElement)) return click({ ref })
        const wanted = String(value).toLowerCase()
        const option = [...el.options].find(o => o.value.toLowerCase() === wanted || o.text.trim().toLowerCase() === wanted) ||
                       [...el.options].find(o => o.text.toLowerCase().includes(wanted))
        if (!option) return { error: 'No option ' + quote(String(value)) + '; options: ' + [...el.options].slice(0, 30).map(o => quote(o.text.trim())).join(', ') }
        el.value = option.value
        el.dispatchEvent(new Event('input', { bubbles: true }))
        el.dispatchEvent(new Event('change', { bubbles: true }))
        return { ok: true }
      }
      const press = ({ ref, key: name }) => {
        const el = (ref && byRef(ref)) || deepActive() || document.body
        const blocked = keyBlocked({ ref, key: name })
        if (blocked) return { error: blocked }
        key(el, name)
        if (name === 'Enter' && el.form) el.form.requestSubmit()
        return { ok: true }
      }
      const scroll = ({ ref, direction = 'down', amount = 0.8 }) => {
        if (ref) { const el = byRef(ref); if (!el) return { error: 'No element ' + ref }; el.scrollIntoView({ block: 'center', behavior: 'instant' }); return { ok: true } }
        const dy = (direction === 'up' ? -1 : direction === 'down' ? 1 : 0) * innerHeight * amount
        const dx = (direction === 'left' ? -1 : direction === 'right' ? 1 : 0) * innerWidth * amount
        scrollBy({ left: dx, top: dy, behavior: 'instant' })
        return { ok: true }
      }
      // Consequential actions wait for the person (unless they let the agent act without asking): spending money, sending
      // or posting something, deleting, booking, and anything that submits a payment form. Judged on what the action
      // would really do: the control clicked (or the one around what was clicked), the form an Enter or submit sends and
      // that form's own submit button, whichever way the agent gets there (a click, Enter, Space, or type with submit).
      const consequential = /\b(buy|pay|purchase|order|checkout|check out|subscribe|unsubscribe|donate|transfer|send|delete|remove|erase|post|publish|tweet|share|reply|book|reserve|rent|confirm|complete|place|sign (contract|agreement)|cancel (subscription|membership|order|account|plan)|close account|deactivate|withdraw|trade|sell|bid|kaufen|bezahlen|bestellen|senden|löschen|acheter|payer|commander|envoyer|supprimer|comprar|pagar|enviar|eliminar|borrar)\b/i
      // Links only for the clearest words: "Order history" or "Share" as a link just goes to a page.
      const consequentialLink = /\b(buy|pay|purchase|checkout|check out|donate|subscribe|delete)\b/i
      const deepActive = () => {
        let el = document.activeElement
        while (el && el.shadowRoot && el.shadowRoot.activeElement) el = el.shadowRoot.activeElement
        return el
      }
      const refusal = kind => kind === 'card'
        ? 'Ikago never lets an agent type card numbers or security codes. Ask the person to take over and fill it.'
        : 'Ikago never lets an agent type into a password field. Ask the person to take over and sign in.'
      // Keys that would type into a password or card field.
      const keyBlocked = ({ ref, key: name }) => {
        const el = (ref && byRef(ref)) || deepActive()
        const sensitive = el && sensitiveOf(el)
        if (sensitive !== 'password' && sensitive !== 'card') return null
        return ['Enter', 'Tab', 'Escape', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'Home', 'End', 'PageUp', 'PageDown'].includes(name)
          ? null : refusal(sensitive)
      }
      const controlOf = el => (el.closest && el.closest('button, input[type=submit i], input[type=image i], input[type=button i], a[href], [role=button], [role=link], [role=menuitem]')) || el
      const submitsForm = control => {
        if (control instanceof HTMLButtonElement) return control.type === 'submit' && control.form
        if (control instanceof HTMLInputElement && ['submit', 'image'].includes(control.type)) return control.form
        return null
      }
      const paymentForm = form => [...form.querySelectorAll('input, select')].some(f =>
        /(^|\s)cc-/.test((f.getAttribute('autocomplete') || '').toLowerCase()) || sensitiveOf(f) === 'card')
      const judge = (control, form) => {
        if (control) {
          const name = nameOf(control)
          const isLink = control.tagName === 'A' || control.getAttribute('role') === 'link'
          if (name && (isLink ? consequentialLink : consequential).test(name)) return name
        }
        if (form) {
          const submitter = form.querySelector('button[type=submit i], input[type=submit i], input[type=image i], button:not([type])')
          if (submitter && consequential.test(nameOf(submitter))) return nameOf(submitter)
          if (paymentForm(form)) return 'a payment form'
        }
        return null
      }
      // `action`: click, key (with `key`), or submit (type with submit). Returns what it would do, if consequential.
      const assess = ({ ref, action, key: name }) => {
        const el = (ref && byRef(ref)) || deepActive()
        if (!el || el === document.body || el === document.documentElement) return { risky: false }
        const field = el instanceof HTMLTextAreaElement || el.isContentEditable ||
          (el instanceof HTMLInputElement && !['submit', 'image', 'button', 'reset', 'checkbox', 'radio'].includes(el.type))
        let what = null
        if (action === 'submit' || (action === 'key' && name === 'Enter' && field && !(el instanceof HTMLTextAreaElement))) {
          // Enter in a field sends its form (implicit submission).
          if (el.form) what = judge(null, el.form)
        } else if (action === 'click' || (action === 'key' && (name === 'Enter' || name === ' ') && !field)) {
          const control = controlOf(el)
          what = judge(control, submitsForm(control))
        }
        return { risky: !!what, what: what || '', site: location.hostname }
      }

      window.__ikagoAgent = { outline, changes, text, find, point, highlight, click, type, select, press, scroll, assess, keyBlocked,
                              focus: ({ ref }) => { const el = byRef(ref); if (!el) return { error: 'No element ' + ref }; el.focus(); return { ok: true } } }
    })()
    """#
}
