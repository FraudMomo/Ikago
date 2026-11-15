import Foundation

/// Picks the page's icon for Ikago's light or dark appearance. Sites can offer one per mode with
/// `<link rel="icon" media="(prefers-color-scheme: dark)">`; the icon sits on Ikago's sidebar, so Ikago's mode
/// decides, not the page's. Runs in the engine's isolated world.
enum FaviconScript {
    static func pick(dark: Bool) -> String {
        """
        ((dark) => {
          const links = [...document.querySelectorAll('link[rel~="icon"], link[rel="apple-touch-icon"]')];
          const isIcon = l => /(^|\\s)icon(\\s|$)/i.test(l.rel);
          const fits = l => {
            const media = (l.media || '').toLowerCase();
            if (!media || media === 'all') return true;
            if (media.includes('prefers-color-scheme')) return media.includes('dark') === dark;
            try { return matchMedia(l.media).matches; } catch { return true; }
          };
          const link = links.find(l => isIcon(l) && l.media && fits(l)) || links.find(l => isIcon(l) && fits(l))
            || links.find(fits);
          return link ? link.href : null;
        })(\(dark))
        """
    }
}
