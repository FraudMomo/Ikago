import Foundation

/// Lets an extension's popup on Chromium see the tab it was opened for. Ikago's pages are embedded
/// Chromium pages with no browser window, so `chrome.tabs.query` can't find them, and without Chrome's
/// toolbar click there is no `activeTab` grant to reveal their address: popups such as uBlock Origin
/// Lite's say "not a website". This layer runs in the popup page only, before its own code, never in a
/// website. Tab and window queries get a stand-in for Ikago's active tab with its real address and
/// title. Reloading it is passed to Ikago through `__ikagoRequests`, which the popup's owner reads;
/// other calls aimed at it fail as they would for a closed tab.
enum ChromiumPopupLayer {
    /// The stand-in tab's ID: far above the IDs Chromium hands out to tabs in practice.
    static let tabID = 2_100_000_000

    static func source(url: String, title: String) -> String {
        let target = (try? JSONSerialization.data(withJSONObject: ["url": url, "title": title])).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        return """
        (() => {
          if (location.protocol !== 'chrome-extension:' || !globalThis.chrome || !chrome.tabs || globalThis.__ikagoPopupLayer) return
          globalThis.__ikagoPopupLayer = true
          globalThis.__ikagoRequests = []
          const target = \(target), ID = \(tabID)
          const tab = {id: ID, index: 0, windowId: -1, openerTabId: undefined, active: true, highlighted: true, selected: true,
                       pinned: false, audible: false, discarded: false, autoDiscardable: true, incognito: false,
                       status: 'complete', url: target.url, title: target.title, groupId: -1,
                       mutedInfo: {muted: false}, width: innerWidth, height: innerHeight}
          const win = {id: -1, focused: true, type: 'normal', state: 'normal', incognito: false, alwaysOnTop: false, tabs: [tab]}
          const tabs = chrome.tabs
          const real = {query: tabs.query.bind(tabs), get: tabs.get.bind(tabs), reload: tabs.reload && tabs.reload.bind(tabs)}
          const gone = () => Promise.reject(new Error('No tab with id: ' + ID + '.'))
          const answer = (promise, callback) => {
            if (typeof callback !== 'function') return promise
            promise.then(value => callback(value), () => callback(undefined))
          }
          const copy = () => Object.assign({}, tab)
          const glob = pattern => new RegExp('^' + pattern.replace(/[.+?^${}()|[\\]\\\\]/g, '\\\\$&').replace(/\\*/g, '.*') + '$')
          const matches = info => !info || !info.url || [].concat(info.url).some(p => glob(p).test(tab.url))

          tabs.query = (info, callback) => answer((async () => {
            info = info || {}
            // "Which tab am I on?" is about Ikago's tab, never the popup's own embedded page.
            if (info.active || info.currentWindow || info.lastFocusedWindow || info.highlighted) return matches(info) ? [copy()] : []
            const others = (await real.query(info).catch(() => [])).filter(t => t.url && !t.url.startsWith(location.origin))
            return (matches(info) ? [copy()] : []).concat(others)
          })(), callback)
          tabs.get = (id, callback) => answer(id === ID ? Promise.resolve(copy()) : real.get(id), callback)
          if (real.reload) tabs.reload = (id, props, callback) => {
            if (typeof id !== 'number') { callback = props; props = id; id = ID }
            if (typeof props === 'function') { callback = props; props = undefined }
            if (id !== ID) return answer(real.reload(id, props || {}), callback)
            globalThis.__ikagoRequests.push(props && props.bypassCache ? 'hard-reload' : 'reload')
            return answer(Promise.resolve(), callback)
          }
          for (const name of ['sendMessage', 'update', 'remove', 'executeScript', 'insertCSS', 'captureVisibleTab']) {
            const original = tabs[name] && tabs[name].bind(tabs)
            if (!original) continue
            tabs[name] = (...args) => args[0] === ID ? (typeof args[args.length - 1] === 'function' ? args[args.length - 1]() : gone()) : original(...args)
          }
          if (chrome.scripting && chrome.scripting.executeScript) {
            const original = chrome.scripting.executeScript.bind(chrome.scripting)
            chrome.scripting.executeScript = (details, callback) =>
              details && details.target && details.target.tabId === ID ? answer(gone(), callback) : original(details, callback)
          }
          if (chrome.windows) {
            const current = (info, callback) => answer(Promise.resolve(Object.assign({}, win, {tabs: [copy()]})), typeof info === 'function' ? info : callback)
            chrome.windows.getCurrent = current
            chrome.windows.getLastFocused = current
          }
        })()
        """
    }
}
