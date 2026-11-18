import Foundation

/// Find in page's Highlight All: every match marked with the CSS Custom Highlight API from Ikago's isolated world.
/// WebKit's own find selects one match at a time; Chromium's native find already marks them all.
enum FindHighlights {
    static let clearScript = """
        if (window.CSS && CSS.highlights) CSS.highlights.delete('ikago-find-all');
        document.getElementById('ikago-find-all-style')?.remove();
        """

    /// A function body (`callAsync`) that finds every match of `text` and returns `{total, active, ticks}`: how many
    /// there are, which one WebKit's find has selected (1-based, 0 when none), and where they sit down the page (0–1,
    /// for the scroll bar's tick marks). With `mark`, Highlight All marks them all; without, earlier marks go.
    static func detailsBody(_ text: String, matchCase: Bool, mark: Bool) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [text])) ?? Data("[\"\"]".utf8)
        let needle = String(decoding: data, as: UTF8.self)
        return """
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
            let active = 0;
            const sel = window.getSelection();
            if (sel && sel.rangeCount && ranges.length) {
                const s = sel.getRangeAt(0);
                for (let i = 0; i < ranges.length; i++) {
                    if (ranges[i].compareBoundaryPoints(Range.START_TO_START, s) === 0) { active = i + 1; break; }
                }
            }
            const height = Math.max(document.documentElement.scrollHeight, document.body ? document.body.scrollHeight : 0, 1);
            const ticks = [], seen = new Set();
            for (const r of ranges) {
                const box = r.getBoundingClientRect();
                if (!box.width && !box.height) continue;
                const at = Math.min(1, Math.max(0, (box.top + window.scrollY) / height));
                const key = Math.round(at * 400);
                if (!seen.has(key)) { seen.add(key); ticks.push(at); }
                if (ticks.length >= 400) break;
            }
            if (window.CSS && CSS.highlights && window.Highlight) {
                // WebKit repaints only what a new highlight covers when one replaces another, so the old one's
                // marks stayed on screen; deleting it first repaints them away.
                CSS.highlights.delete('ikago-find-all');
                if (\(mark)) {
                    CSS.highlights.set('ikago-find-all', new Highlight(...ranges));
                    if (!document.getElementById('ikago-find-all-style')) {
                        const st = document.createElement('style');
                        st.id = 'ikago-find-all-style';
                        st.textContent = '::highlight(ikago-find-all){background-color:rgba(255,212,0,.45)}';
                        (document.head || document.documentElement).appendChild(st);
                    }
                }
            }
            let activeTick = -1;
            if (active) {
                const box = ranges[active - 1].getBoundingClientRect();
                activeTick = Math.min(1, Math.max(0, (box.top + window.scrollY) / height));
            }
            return {total: ranges.length, active, ticks, activeTick};
            """
    }
}
