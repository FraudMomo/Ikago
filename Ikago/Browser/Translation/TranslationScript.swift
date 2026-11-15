import Foundation

/// Reads a page's text and writes the translation back, in the browser's isolated world: only text nodes change
/// (never markup, scripts or form values), the originals are kept to restore, and code, editable and `translate=no`
/// text is left alone.
enum TranslationScript {
    static let collect = #"""
    (() => {
      window.__ikagoTranslate?.restore();
      const SKIP = new Set(['SCRIPT','STYLE','NOSCRIPT','TEXTAREA','CODE','PRE','SVG','CANVAS','INPUT','SELECT','OPTION','KBD','SAMP','TITLE']);
      const nodes = [], originals = [];
      let total = 0;
      const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
        acceptNode: node => {
          const parent = node.parentElement;
          if (!parent || SKIP.has(parent.tagName.toUpperCase())) return NodeFilter.FILTER_REJECT;
          if (parent.closest('[translate=no],.notranslate,[contenteditable=""],[contenteditable=true],[hidden],[aria-hidden=true],code,pre')) return NodeFilter.FILTER_REJECT;
          return /\p{L}{2}/u.test(node.nodeValue) ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT;
        }
      });
      while (walker.nextNode()) {
        const node = walker.currentNode, value = node.nodeValue;
        if (nodes.length >= 4000 || total + value.length > 90000) break;
        nodes.push(node); originals.push(value); total += value.length;
      }
      const parts = value => { const lead = value.match(/^\s*/)[0], trail = value.match(/\s*$/)[0]; return [lead, value.trim().replace(/\s+/g, ' '), trail]; };
      window.__ikagoTranslate = {
        apply(list) {
          for (const [index, text] of list) {
            const node = nodes[index];
            if (!node || !node.isConnected) continue;
            const [lead, , trail] = parts(originals[index]);
            node.nodeValue = lead + text + trail;
          }
        },
        restore() {
          nodes.forEach((node, index) => { if (node.isConnected) node.nodeValue = originals[index]; });
          delete window.__ikagoTranslate;
        }
      };
      return {lang: document.documentElement.lang || '', texts: originals.map(value => parts(value)[1])};
    })()
    """#

    static func apply(_ list: [(Int, String)]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: list.map { [$0.0, $0.1] }),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return "window.__ikagoTranslate?.apply(\(json))"
    }

    static let restore = "window.__ikagoTranslate?.restore()"
}
