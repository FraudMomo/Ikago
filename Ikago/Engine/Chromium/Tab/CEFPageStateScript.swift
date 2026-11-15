import Foundation

/// Reports changes from an explicitly registered isolated context. No clock, network bridge or page-world code.
enum CEFPageStateScript {
    static let source = """
    \(MediaPlaybackScript.install)
    (() => {
      if (window.__ikagoPageState) return;
      let last = '', queued = false, theme = '', color = null, canvas, pip = 0;
      const report = () => {
        queued = false;
        const value = document.querySelector('meta[name="theme-color"]')?.content || '';
        if (value !== theme) {
          theme = value; color = null;
          if (value && CSS.supports('color', value)) {
            canvas ||= document.createElement('canvas'); canvas.width = canvas.height = 1;
            const context = canvas.getContext('2d');
            context.clearRect(0, 0, 1, 1); context.fillStyle = value; context.fillRect(0, 0, 1, 1);
            color = [...context.getImageData(0, 0, 1, 1).data];
          }
        }
        const json = JSON.stringify({media: window.__ikagoMedia.state(), color, pip});
        if (json !== last) { last = json; window.__ikagoStateChanged(json); }
      };
      const changed = () => { if (!queued) { queued = true; queueMicrotask(report); } };
      window.__ikagoMediaChanged = changed;
      // The page asked for Picture in Picture (YouTube's button): Ikago takes it into its own panel.
      document.addEventListener('enterpictureinpicture', () => { pip += 1; changed(); }, true);
      const observeHead = () => {
        if (document.head) new MutationObserver(changed).observe(document.head,
          {subtree: true, childList: true, characterData: true, attributes: true, attributeFilter: ['content', 'href']});
        changed();
      };
      if (document.head) observeHead();
      else document.addEventListener('DOMContentLoaded', observeHead, {once: true});
      window.__ikagoPageState = true;
      report();
    })();
    """
}
