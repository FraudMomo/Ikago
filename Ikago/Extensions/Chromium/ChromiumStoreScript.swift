/// The Chrome Web Store's "Add to Chrome" button as "Add to Ikago", on Chromium. Runs in the "ikago-store"
/// isolated world of chromewebstore.google.com; the page can't see it. It never messages Ikago: native code
/// sets each extension's state with `set`, and asks `hit(x, y)` whether a real click landed on the button.
enum ChromiumStoreScript {
    static let world = "ikago-store"

    static let source = #"""
    (() => {
      if (window.__ikagoStore || location.host !== 'chromewebstore.google.com' || window !== window.top) return
      const extensionID = () => (location.pathname.match(/\/detail\/(?:[^/]+\/)?([a-p]{32})/) || [])[1]
      const labels = /^(Add to Chrome|Remove from Chrome|Add to Ikago|Added to Ikago|Adding…|Checking…|Couldn’t add)$/
      const status = {}  // id → {state, reason}: checking, none, adding, installed, error
      let bound = null

      const button = () => [...document.querySelectorAll('button')].find(b => labels.test(b.innerText.trim()))
      const label = state => ({installed: 'Added to Ikago', adding: 'Adding…', checking: 'Checking…', error: 'Add to Ikago'})[state] || 'Add to Ikago'
      const active = state => state === 'none' || state === 'error'

      const render = () => {
        const id = extensionID(), target = id && button()
        if (!target) return
        const info = status[id] || {state: 'checking'}
        const text = [...target.querySelectorAll('span')].find(n => !n.children.length && labels.test(n.textContent.trim())) || target
        if (text.textContent !== label(info.state)) text.textContent = label(info.state)
        target.setAttribute('aria-disabled', String(!active(info.state)))
        target.style.setProperty('background', active(info.state) ? '#0b57d0' : 'rgba(127,127,127,0.18)', 'important')
        target.style.setProperty('color', active(info.state) ? '#fff' : 'inherit', 'important')
        target.style.setProperty('cursor', active(info.state) ? 'pointer' : 'default', 'important')
        let note = document.getElementById('ikago-store-note')
        if (info.reason) {
          if (!note) {
            note = document.createElement('p')
            note.id = 'ikago-store-note'
            note.setAttribute('role', 'status')
            note.style.cssText = 'font:14px system-ui;max-width:520px;margin:12px 0;line-height:1.5'
            target.parentElement.appendChild(note)
          }
          if (note.textContent !== info.reason) note.textContent = info.reason
        } else if (note) note.remove()
        // Chrome's own install flow doesn't exist here; Ikago handles the click instead.
        if (bound !== target) {
          bound = target
          target.addEventListener('click', event => { event.preventDefault(); event.stopImmediatePropagation() }, true)
        }
      }

      // Google's "Switch to Chrome" banner and popup don't apply here. Gives up after a while.
      let nagChecks = 0
      const banners = new Set(['Switch to Chrome to install extensions and themes', 'Install Chrome'])
      const hideNags = () => {
        if (nagChecks++ > 60 || !document.body) return
        const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT)
        while (walker.nextNode()) {
          const text = walker.currentNode.textContent.trim()
          if (!banners.has(text)) continue
          let box = walker.currentNode.parentElement
          while (box.parentElement && box.parentElement.textContent.trim() === text) box = box.parentElement
          box.style.setProperty('display', 'none', 'important')
        }
        const decline = [...document.querySelectorAll('[role="dialog"] button, [aria-modal="true"] button')]
          .find(b => b.textContent.trim() === 'No thanks')
        if (decline) decline.click()
      }

      let queued = false
      new MutationObserver(() => {
        if (queued) return
        queued = true
        setTimeout(() => { queued = false; render(); hideNags() }, 50)
      }).observe(document.documentElement, {childList: true, subtree: true, characterData: true})

      window.__ikagoStore = {
        current: () => extensionID() || null,
        set: (id, state, reason) => { status[id] = {state, reason: reason || ''}; render() },
        // The extension to add when a real click at this viewport point hit the button, else null.
        hit: (x, y) => {
          const id = extensionID(), target = id && button()
          if (!target || !active((status[id] || {}).state)) return null
          const r = target.getBoundingClientRect()
          if (x < r.left || x > r.right || y < r.top || y > r.bottom) return null
          status[id] = {state: 'adding', reason: ''}
          render()
          return id
        }
      }
      render()
      hideNags()
    })()
    """#
}
