import Foundation

/// Find in page's Highlight All: every match marked with the CSS Custom Highlight API from Ikago's isolated world.
/// WebKit's own find selects one match at a time; Chromium's native find already marks them all.
enum FindHighlights {
    static let clearScript = """
        if (window.CSS && CSS.highlights) CSS.highlights.delete('ikago-find-all');
        document.getElementById('ikago-find-all-style')?.remove();
        """

    /// A function body (`callAsync`) that marks every match of `text` and returns how many there are.
    static func markBody(_ text: String, matchCase: Bool) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [text])) ?? Data("[\"\"]".utf8)
        let needle = String(decoding: data, as: UTF8.self)
        return """
            if (!(window.CSS && CSS.highlights && window.Highlight)) return -1;
            const cs = \(matchCase), raw = \(needle)[0], n = cs ? raw : raw.toLowerCase();
            const ranges = [];
            if (n.length) {
                const skip = new Set(['SCRIPT', 'STYLE', 'NOSCRIPT', 'TEXTAREA']);
                const walker = document.createTreeWalker(document.body || document.documentElement, NodeFilter.SHOW_TEXT, {
                    acceptNode(node) {
                        const p = node.parentElement;
                        return p && !skip.has(p.tagName) ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT;
                    }
                });
                for (let node = walker.nextNode(); node && ranges.length < 5000; node = walker.nextNode()) {
                    const hay = cs ? node.data : node.data.toLowerCase();
                    for (let i = hay.indexOf(n); i !== -1 && ranges.length < 5000; i = hay.indexOf(n, i + n.length)) {
                        const r = new Range(); r.setStart(node, i); r.setEnd(node, i + n.length); ranges.push(r);
                    }
                }
            }
            CSS.highlights.set('ikago-find-all', new Highlight(...ranges));
            if (!document.getElementById('ikago-find-all-style')) {
                const s = document.createElement('style');
                s.id = 'ikago-find-all-style';
                s.textContent = '::highlight(ikago-find-all){background-color:rgba(255,212,0,.45)}';
                (document.head || document.documentElement).appendChild(s);
            }
            return ranges.length;
            """
    }
}
