import Foundation

/// Finds a page's article and returns it as a small, sanitized document, in the browser's isolated world (the page
/// can't see or change it). The article is the container whose paragraphs hold most of the page's text; everything
/// that isn't an allowed tag is unwrapped or dropped, links and images keep only absolute http(s) addresses, and no
/// attribute but `href`, `src`, `alt` and `colspan` survives, so the result can't run anything.
enum ReaderScript {
    static let extract = #"""
    (() => {
      const DROP = 'script,style,noscript,iframe,object,embed,form,nav,aside,footer,button,input,select,textarea,svg,canvas,dialog,video,audio,[role=navigation],[role=banner],[role=complementary],[role=search],[aria-hidden=true],[hidden]';
      const NOISE = /(^|[\s_-])(comments?|share|sharing|social|sidebar|related|recommended|promo|advert|ads?|newsletter|subscribe|cookie|popup|modal|breadcrumbs?|toolbar|menu|footer|banner|byline-share|tags?)([\s_-]|$)/i;
      const text = el => (el.textContent || '').replace(/\s+/g, ' ').trim();
      const linkDensity = el => { const total = text(el).length || 1; let links = 0; el.querySelectorAll('a').forEach(a => { links += text(a).length; }); return links / total; };
      const scores = new Map();
      for (const p of document.body.querySelectorAll('p, pre, blockquote')) {
        if (p.closest(DROP)) continue;
        const own = text(p), length = own.length;
        if (length < 60) continue;
        const score = 1 + Math.min(3, Math.floor(length / 100)) + own.split(',').length * 0.5;
        let node = p.parentElement;
        for (let depth = 0; node && node !== document.documentElement && depth < 3; depth++, node = node.parentElement) {
          if (node === document.body && depth > 0) break;
          scores.set(node, (scores.get(node) || 0) + score / (depth === 0 ? 1 : depth === 1 ? 2 : 4));
        }
      }
      let best = null, top = 0;
      for (const [node, score] of scores) {
        const adjusted = score * (1 - linkDensity(node));
        if (adjusted > top) { best = node; top = adjusted; }
      }
      if (!best || top < 12) return null;
      const article = best.closest('article');
      if (article && text(article).length < text(best).length * 1.6) best = article;
      while (best.parentElement && best.parentElement !== document.body && best.parentElement.tagName !== 'HTML'
             && text(best.parentElement).length < text(best).length * 1.2 && !best.parentElement.closest('header,footer,nav')) best = best.parentElement;
      if (text(best).length < 400) return null;

      const clone = best.cloneNode(true);
      clone.querySelectorAll(DROP).forEach(node => node.remove());
      // The byline goes under the headline, not into the text too.
      clone.querySelectorAll('[rel=author],[itemprop=author],.byline,.author,[class*=byline]').forEach(node => { if (text(node).length < 160) node.remove(); });
      for (const node of [...clone.querySelectorAll('*')]) {
        if (!node.isConnected) continue;
        const label = (node.className && node.className.baseVal === undefined ? node.className : '') + ' ' + (node.id || '');
        const length = text(node).length;
        if (node.tagName !== 'ARTICLE' && ((NOISE.test(label) && (length < 500 || linkDensity(node) > 0.3))
            || (linkDensity(node) > 0.6 && length < 300 && !node.querySelector('img,p')))) node.remove();
      }
      const base = document.baseURI;
      const absolute = value => { try { const url = new URL(value, base); return /^https?:$/.test(url.protocol) ? url.href : ''; } catch (error) { return ''; } };
      const escape = value => value.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
      const KEEP = new Set(['p','h1','h2','h3','h4','h5','h6','ul','ol','li','blockquote','pre','code','em','strong','b','i','u','s','sub','sup','br','hr','figure','figcaption','table','thead','tbody','tr','th','td','a','img','abbr','cite','q','small','mark','kbd','dl','dt','dd']);
      const BLOCK = new Set(['p','div','section','article','main','ul','ol','li','table','blockquote','pre','h1','h2','h3','h4','h5','h6','figure','hr','dl']);
      const walk = node => {
        if (node.nodeType === 3) return escape(node.nodeValue);
        if (node.nodeType !== 1) return '';
        const tag = node.tagName.toLowerCase();
        const inner = () => [...node.childNodes].map(walk).join('');
        if (tag === 'img') {
          const src = absolute(node.currentSrc || node.getAttribute('src') || node.dataset.src || '');
          if (!src) return '';
          if ((node.naturalWidth && node.naturalWidth < 80) || (node.width && node.width < 40)) return '';
          return '<img src="' + escape(src) + '" alt="' + escape(node.getAttribute('alt') || '') + '">';
        }
        if (tag === 'picture') return inner();
        if (tag === 'a') {
          const href = absolute(node.getAttribute('href') || '');
          const body = inner();
          return href && body.trim() ? '<a href="' + escape(href) + '">' + body + '</a>' : body;
        }
        if (tag === 'div' || tag === 'section' || tag === 'main' || tag === 'article' || tag === 'span' || tag === 'center') {
          const hasBlock = [...node.children].some(child => BLOCK.has(child.tagName.toLowerCase()) || child.tagName === 'FIGURE' || child.tagName === 'IMG' || child.tagName === 'PICTURE');
          const body = inner();
          return tag !== 'span' && !hasBlock && body.trim() ? '<p>' + body + '</p>' : body;
        }
        if (!KEEP.has(tag)) return inner();
        const body = inner();
        if (!body.trim() && !['br', 'hr'].includes(tag)) return '';
        if (tag === 'br' || tag === 'hr') return '<' + tag + '>';
        const extra = (tag === 'td' || tag === 'th') && node.colSpan > 1 ? ' colspan="' + Math.min(node.colSpan, 20) + '"' : '';
        return '<' + tag + extra + '>' + body + '</' + tag + '>';
      };
      let html = walk(clone);
      const meta = name => document.querySelector('meta[property="' + name + '"],meta[name="' + name + '"]')?.content?.trim() || '';
      const heading = best.querySelector('h1');
      const title = (heading && text(heading).length > 8 ? text(heading) : '') || meta('og:title') || document.title || '';
      if (heading) {
        const first = html.match(/^\s*<h1>([\s\S]*?)<\/h1>/);
        if (first) html = html.slice(first[0].length);
      }
      const bylineNode = document.querySelector('[rel=author],[itemprop=author],.byline,.author,[class*=byline]');
      const byline = (meta('author') || meta('article:author') || (bylineNode ? text(bylineNode) : '')).slice(0, 120);
      const site = meta('og:site_name') || location.hostname.replace(/^www\./, '');
      return {title: title.slice(0, 300), byline, site: site.slice(0, 80), lang: document.documentElement.lang || '',
              dir: document.documentElement.dir || getComputedStyle(document.documentElement).direction || 'ltr', html};
    })()
    """#
}
