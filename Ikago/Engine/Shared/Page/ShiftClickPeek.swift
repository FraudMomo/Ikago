import Foundation

/// Shift-click on a link, caught before the page's own scripts see the click. Sites that route links in JavaScript
/// (Instagram, X, most single-page apps) cancel the navigation Ikago would otherwise notice, and do their own thing
/// with the click. Runs in Ikago's isolated world, at the window's capture phase, so it is first in line; the page sees
/// no click at all. The browser then peeks the link, or opens it in a new tab with Peek off, as before.
enum ShiftClickPeek {
    /// A listener that hands the link's address to `post` (a JavaScript expression taking the address).
    static func listener(post: String) -> String {
        """
        window.addEventListener('click', event => {
          if (!event.isTrusted || event.button !== 0 || !event.shiftKey || event.metaKey || event.ctrlKey || event.altKey) return;
          const link = event.composedPath().find(node => node instanceof Element && node.matches('a[href], area[href]'));
          if (!link || link.hasAttribute('download') || !/^https?:/i.test(link.href)) return;
          event.preventDefault();
          event.stopImmediatePropagation();
          try { (\(post))(String(link.href).slice(0, 4096)); } catch (error) {}
        }, true);
        """
    }

    /// The page's report, checked: only web addresses peek.
    static func url(_ value: Any?) -> URL? {
        guard let text = value as? String, text.count <= 4096, let url = URL(string: text),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }
}
