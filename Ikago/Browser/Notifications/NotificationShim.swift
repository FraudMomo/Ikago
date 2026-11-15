import Foundation

/// The page-facing Notification API, for both engines. Chromium shows nothing for a page's notification and WebKit
/// has no public hook, so a small script in the page's own world stands in for `Notification` and talks to Ikago in
/// JSON. It only asks: Ikago decides from the site's saved choice (`WebNotifications`) and the page can't grant itself
/// anything. Top documents on secure origins only.
enum NotificationShim {
    /// WebKit posts to its message handler; Chromium raises an event that the page-state script (an isolated world)
    /// relays through its DevTools binding.
    static let webKitHandler = "ikagoNotify"
    static let event = "__ikago_notify"
    static let reply = "__ikago_notify_reply"

    static var webKit: String { source(send: "(text => window.webkit.messageHandlers.\(webKitHandler).postMessage(text))") }
    static var chromium: String {
        source(send: "(text => window.dispatchEvent(new CustomEvent('\(event)', {detail: text})))")
    }

    private static func source(send: String) -> String {
        """
        (() => {
          if (window.top !== window || !window.isSecureContext || (window.Notification && window.Notification.__ikago)) return;
          const send = \(send);
          const native = window.Notification;
          let permission = 'default', next = 0;
          const asking = new Map(), live = new Map();
          const post = message => { try { send(JSON.stringify(message)); } catch (error) {} };
          const text = (value, limit) => value == null ? '' : String(value).slice(0, limit);
          class Notification extends EventTarget {
            static get permission() { return permission; }
            static get maxActions() { return 0; }
            static requestPermission(callback) {
              const id = ++next;
              const promise = new Promise(resolve => { asking.set(id, resolve); post({t: 'request', id}); });
              if (typeof callback === 'function') promise.then(callback);
              return promise;
            }
            constructor(title, options = {}) {
              super();
              if (arguments.length === 0) throw new TypeError("Failed to construct 'Notification': 1 argument required, but only 0 present.");
              this.title = text(title, 256);
              this.body = text(options.body, 2000);
              this.tag = text(options.tag, 256);
              this.icon = text(options.icon, 2048);
              this.lang = text(options.lang, 32);
              this.dir = ['ltr', 'rtl'].includes(options.dir) ? options.dir : 'auto';
              this.silent = options.silent === true ? true : null;
              this.data = options.data === undefined ? null : options.data;
              this.requireInteraction = options.requireInteraction === true;
              this.timestamp = Date.now();
              this.onclick = this.onshow = this.onclose = this.onerror = null;
              const id = ++next;
              Object.defineProperty(this, '__id', {value: id});
              live.set(id, this);
              post({t: 'show', id, title: this.title, body: this.body, tag: this.tag, silent: this.silent === true});
            }
            close() { post({t: 'close', id: this.__id}); }
          }
          const fire = (target, name) => {
            const event = new Event(name);
            const handler = target['on' + name];
            if (typeof handler === 'function') { try { handler.call(target, event); } catch (error) {} }
            target.dispatchEvent(event);
          };
          window.addEventListener('\(reply)', event => {
            let message;
            try { message = JSON.parse(event.detail); } catch (error) { return; }
            if (message.t === 'permission') permission = message.value;
            else if (message.t === 'request') {
              permission = message.value;
              const resolve = asking.get(message.id);
              asking.delete(message.id);
              if (resolve) resolve(permission);
            } else if (message.t === 'event') {
              const target = live.get(message.id);
              if (!target) return;
              if (message.name === 'close' || message.name === 'error') live.delete(message.id);
              fire(target, message.name);
            }
          });
          Object.defineProperty(Notification, '__ikago', {value: true});
          Object.defineProperty(window, 'Notification', {value: Notification, writable: true, configurable: true});
          if (window.ServiceWorkerRegistration) {
            ServiceWorkerRegistration.prototype.showNotification = function (title, options) {
              new Notification(title, options);
              return Promise.resolve();
            };
          }
          post({t: 'permission'});
        })();
        """
    }
}

extension NotificationShim {
    /// The script that hands a message to the page's shim (run in the page's own world).
    static func replyScript(_ message: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: message), let json = String(data: data, encoding: .utf8),
              let literal = try? JSONEncoder().encode(json), let text = String(data: literal, encoding: .utf8) else { return nil }
        return "window.dispatchEvent(new CustomEvent('\(reply)', {detail: \(text)}))"
    }
}
