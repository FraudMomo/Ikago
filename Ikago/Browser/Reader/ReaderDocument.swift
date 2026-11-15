import Foundation

/// What the page's article looked like to `ReaderScript`.
struct ReaderArticle {
    let title: String
    let byline: String
    let site: String
    let lang: String
    let rtl: Bool
    let html: String

    init?(_ value: Any?) {
        guard let object = value as? [String: Any], let html = object["html"] as? String, !html.isEmpty else { return nil }
        title = object["title"] as? String ?? ""
        byline = object["byline"] as? String ?? ""
        site = object["site"] as? String ?? ""
        lang = object["lang"] as? String ?? ""
        rtl = object["dir"] as? String == "rtl"
        self.html = html
    }
}

/// The reader's look: a font, a size and a theme, kept in Settings' preferences.
struct ReaderStyle: Equatable {
    enum Theme: String, CaseIterable { case auto, light, sepia, dark
        var title: String { rawValue.capitalized }
    }
    enum Font: String, CaseIterable { case serif, sans
        var title: String { self == .serif ? "Serif" : "Sans-serif" }
    }
    static let sizes = 15...30
    var font = Font.serif
    var size = 19
    var theme = Theme.auto

    init(_ preferences: BrowserPreferences) {
        font = Font(rawValue: preferences.readerFont ?? "") ?? .serif
        size = min(Self.sizes.upperBound, max(Self.sizes.lowerBound, preferences.readerSize ?? 19))
        theme = Theme(rawValue: preferences.readerTheme ?? "") ?? .auto
    }

    /// `auto` follows the window's light or dark mode.
    func resolvedTheme(dark: Bool) -> String { theme == .auto ? (dark ? "dark" : "light") : theme.rawValue }
}

/// The reader page: the article under a headline, in a quiet column. No scripts run in it (the article is sanitized and
/// the policy allows none); its look comes from the style variables on the root element, which change in place.
enum ReaderDocument {
    static func html(_ article: ReaderArticle?, style: ReaderStyle, dark: Bool) -> String {
        let body: String
        if let article {
            let meta = [article.byline, article.site].filter { !$0.isEmpty }.joined(separator: " · ")
            body = """
            <article lang="\(escape(article.lang))" dir="\(article.rtl ? "rtl" : "ltr")">
            <header><h1>\(escape(article.title))</h1>\(meta.isEmpty ? "" : "<p class=meta>\(escape(meta))</p>")</header>
            \(article.html)
            </article>
            """
        } else {
            body = "<div class=empty><h1>No article found</h1><p>This page doesn’t look like an article, so there is nothing to simplify.</p></div>"
        }
        return """
        <!doctype html><html data-theme="\(style.resolvedTheme(dark: dark))" data-font="\(style.font.rawValue)" style="--size:\(style.size)px">
        <head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src https: http:; style-src 'unsafe-inline'">
        <meta name="referrer" content="no-referrer"><style>\(css)</style></head><body>\(body)</body></html>
        """
    }

    static func script(_ style: ReaderStyle, dark: Bool) -> String {
        "document.documentElement.dataset.theme='\(style.resolvedTheme(dark: dark))';document.documentElement.dataset.font='\(style.font.rawValue)';document.documentElement.style.setProperty('--size','\(style.size)px')"
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static let css = """
    :root{color-scheme:light dark;--bg:#fbfbfa;--text:#1d1d1f;--muted:#6e6e73;--rule:#e3e3e0;--link:#0a60d6;--code:#f0f0ee}
    [data-theme=sepia]{color-scheme:light;--bg:#f4ecd8;--text:#4a392a;--muted:#8a7660;--rule:#e2d6bb;--link:#8a4b14;--code:#eadfc5}
    [data-theme=dark]{color-scheme:dark;--bg:#1c1c1e;--text:#e6e6e8;--muted:#98989f;--rule:#38383b;--link:#6cb2ff;--code:#2a2a2d}
    [data-font=serif]{--face:ui-serif,'New York',Georgia,serif}[data-font=sans]{--face:-apple-system,'SF Pro Text',system-ui,sans-serif}
    html{background:var(--bg)}
    body{margin:0;padding:72px 28px 120px;background:var(--bg);color:var(--text);font:var(--size)/1.62 var(--face);-webkit-font-smoothing:antialiased;text-rendering:optimizeLegibility}
    article,.empty{max-width:42em;margin:0 auto}
    h1{font:700 1.75em/1.2 var(--face);letter-spacing:-.01em;margin:0 0 .35em}
    h2,h3,h4,h5,h6{font-family:var(--face);line-height:1.25;margin:1.6em 0 .5em}h2{font-size:1.35em}h3{font-size:1.15em}h4,h5,h6{font-size:1em}
    .meta{color:var(--muted);font:500 .72em/1.4 -apple-system,system-ui,sans-serif;margin:0 0 2.2em;padding-bottom:1.4em;border-bottom:1px solid var(--rule)}
    p,ul,ol,dl,pre,table,figure,blockquote{margin:0 0 1.15em}
    a{color:var(--link);text-decoration-thickness:1px;text-underline-offset:.15em}
    img{max-width:100%;height:auto;border-radius:8px;display:block;margin:1.4em auto}
    figure{margin-left:0;margin-right:0}figcaption{color:var(--muted);font:.75em/1.45 -apple-system,system-ui,sans-serif;text-align:center;margin-top:-.8em}
    blockquote{margin-left:0;padding-left:1.1em;border-left:3px solid var(--rule);color:var(--muted)}
    pre,code,kbd{font:.84em/1.5 ui-monospace,Menlo,monospace;background:var(--code);border-radius:6px}code,kbd{padding:.1em .35em}pre{padding:1em;overflow-x:auto}pre code{padding:0;background:none}
    table{border-collapse:collapse;display:block;overflow-x:auto;font-size:.85em}td,th{border:1px solid var(--rule);padding:.4em .7em;text-align:start}
    hr{border:0;border-top:1px solid var(--rule);margin:2em 0}
    .empty{text-align:center;padding-top:20vh;color:var(--muted)}.empty h1{color:var(--text);font-size:1.3em}
    ::selection{background:color-mix(in srgb,var(--link) 30%,transparent)}
    """
}
