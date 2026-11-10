import WebKit

/// Turns the Chrome Web Store's own "Add to Chrome" button into "Add to Ikago".
/// The script runs in the isolated `.defaultClient` world on chromewebstore.google.com only;
/// clicks go through the normal install sheet, so a page can't install anything by itself.
@MainActor
final class WebStoreBridge: NSObject, WKScriptMessageHandlerWithReply {
    static let shared = WebStoreBridge()
    static let handlerName = "ikagoStore"

    func install(in controller: WKUserContentController) {
        controller.addUserScript(WKUserScript(source: Self.source, injectionTime: .atDocumentEnd,
                                              forMainFrameOnly: true, in: .defaultClient))
        controller.addScriptMessageHandler(self, contentWorld: .defaultClient, name: Self.handlerName)
    }

    /// Returns structured compatibility status and a plain-language reason.
    func userContentController(_ controller: WKUserContentController,
                               didReceive message: WKScriptMessage) async -> (Any?, String?) {
        guard message.frameInfo.isMainFrame, message.frameInfo.securityOrigin.protocol == "https",
              message.frameInfo.securityOrigin.host == "chromewebstore.google.com",
              let body = message.body as? [String: Any], let id = body["id"] as? String,
              WebStoreInstaller.isValidID(id) else { return (nil, "invalid request") }
        switch body["action"] as? String {
        case "status":
            return (await ExtensionStoreStatus.shared.status(id), nil)
        case "install":
            guard let browser = ExtensionManager.shared.browser else { return (nil, "no browser window") }
            if await browser.installFromWebStore(id: id) { return (["state": "installed", "reason": "Added to Ikago"], nil) }
            let reason = ExtensionManager.shared.installIssue ?? "Installation was canceled."
            return (["state": reason.hasPrefix("Not supported") ? "unsupported" : "error", "reason": reason], nil)
        default:
            return (nil, "unknown action")
        }
    }

    static let source = """
        (() => {
          if (location.host !== 'chromewebstore.google.com') return
          const bridge = window.webkit.messageHandlers.\(handlerName)
          const ask = (action, id) => bridge.postMessage({ action, id })
          const extensionID = () => (location.pathname.match(/\\/detail\\/(?:[^/]+\\/)?([a-p]{32})/) || [])[1]
          const labels = /^(Add to Chrome|Remove from Chrome|Add to Ikago|Add to Ikago \\(Limited\\)|Added to Ikago|Adding…|Checking compatibility…|Not supported in Ikago)$/
          const status = {}  // id → compatibility status and reason

          const render = (button, id) => {
            const info = status[id] || {state: 'checking'}
            const s = info.state
            const label = s === 'installed' ? 'Added to Ikago' : s === 'unsupported' ? 'Not supported in Ikago' : s === 'checking' ? 'Checking compatibility…' : s === 'adding' ? 'Adding…' : s === 'limited' ? 'Add to Ikago (Limited)' : 'Add to Ikago'
            const text = [...button.querySelectorAll('span')].find(n => !n.children.length && labels.test(n.textContent.trim())) || button
            if (text.textContent !== label) text.textContent = label
            button.disabled = !['none', 'limited', 'error'].includes(s)
            button.setAttribute('aria-disabled', String(button.disabled))
            let note = document.getElementById('ikago-compatibility')
            if (!note) {
              note = document.createElement('p')
              note.id = 'ikago-compatibility'
              note.setAttribute('role', 'status')
              note.style.cssText = 'font:14px system-ui;max-width:520px;margin:12px 0;line-height:1.5'
              button.parentElement.appendChild(note)
            }
            const reason = info.reason || 'Checking extension compatibility with Ikago…'
            if (note.textContent !== reason) note.textContent = reason
            const active = ['none', 'limited', 'error'].includes(s)
            button.style.setProperty('background', active ? '#0b57d0' : 'rgba(127,127,127,0.18)', 'important')
            button.style.setProperty('color', active ? '#fff' : 'inherit', 'important')
            button.style.setProperty('opacity', '1', 'important')
            button.style.setProperty('cursor', active ? 'pointer' : 'default', 'important')
          }

          const bind = (button, id) => {
            if (button.dataset.ikagoBound) return
            button.dataset.ikagoBound = 'true'
            button.addEventListener('click', async event => {
              event.preventDefault()
              event.stopImmediatePropagation()
              const id = extensionID()
              if (!id || !['none', 'limited', 'error'].includes(status[id]?.state)) return
              status[id] = {state: 'adding', reason: 'Waiting for installation…'}
              render(button, id)
              status[id] = await ask('install', id).catch(() => ({state: 'error', reason: 'Could not check compatibility. Try again.'}))
              if (extensionID() === id) render(button, id)
            }, true)
          }

          const patch = async () => {
            const id = extensionID()
            const button = id && [...document.querySelectorAll('button')].find(b => labels.test(b.innerText.trim()))
            if (!button) return
            if (!(id in status)) {
              status[id] = {state: 'checking'}
              render(button, id)
              status[id] = await ask('status', id).catch(() => ({state: 'error', reason: 'Could not check compatibility. Try again.'}))
            }
            if (extensionID() !== id || !button.isConnected) return
            bind(button, id)
            render(button, id)
          }

          // Google's "Switch to Chrome" banner and popup don't apply here: hide the banner,
          // decline the popup. Gives up after a while so it never keeps scanning.
          let nagChecks = 0
          const banners = new Set(['Switch to Chrome to install extensions and themes', 'Install Chrome'])
          const hideNags = () => {
            if (nagChecks++ > 60) return
            const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT)
            while (walker.nextNode()) {
              const text = walker.currentNode.textContent.trim()
              if (!banners.has(text)) continue
              // The largest box holding only this text is the banner itself.
              let box = walker.currentNode.parentElement
              while (box.parentElement && box.parentElement.textContent.trim() === text) box = box.parentElement
              box.style.setProperty('display', 'none', 'important')
            }
            const decline = [...document.querySelectorAll('[role="dialog"] button, [aria-modal="true"] button')]
              .find(b => b.textContent.trim() === 'No thanks')
            decline?.click()
          }

          let queued = false
          new MutationObserver(() => {
            if (queued) return
            queued = true
            requestAnimationFrame(() => { queued = false; patch(); hideNags() })
          }).observe(document.documentElement, { childList: true, subtree: true, characterData: true })
          setInterval(async () => {
            const id = extensionID()
            if (!id || !['installed', 'error'].includes(status[id]?.state)) return
            status[id] = await ask('status', id).catch(() => status[id])
            patch()
          }, 30000)
          patch()
          hideNags()
        })()
        """
}
