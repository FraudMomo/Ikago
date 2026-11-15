import AppKit
import SwiftUI
import WebKit

/// Reader mode over a page: the article in a quiet column (`ReaderDocument`) with a small floating control for the
/// look. The page underneath keeps running and returns when the reader closes (Esc, ✕, or the page navigating).
@MainActor
final class ReaderOverlay: NSView, WKNavigationDelegate {
    private let web: WKWebView
    private let state: BrowserState
    private var controls: NSHostingView<ReaderControls>?
    var onClose: () -> Void = {}
    var onOpen: (URL) -> Void = { _ in }

    init(article: ReaderArticle?, state: BrowserState) {
        self.state = state
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        web = WKWebView(frame: .zero, configuration: configuration)
        super.init(frame: .zero)
        autoresizingMask = [.width, .height]
        wantsLayer = true
        web.navigationDelegate = self
        web.setValue(false, forKey: "drawsBackground")
        web.autoresizingMask = [.width, .height]
        addSubview(web)
        web.loadHTMLString(ReaderDocument.html(article, style: ReaderStyle(state.browserPreferences), dark: state.isDark), baseURL: nil)
        let hosting = NSHostingView(rootView: ReaderControls(state: state, apply: { [weak self] in self?.applyStyle() }, close: { [weak self] in self?.onClose() }))
        // Near the window's top the title bar's safe area would push the pill below its own frame, out of reach of clicks.
        hosting.safeAreaRegions = []
        hosting.frame = NSRect(x: 0, y: 0, width: 96, height: 34)
        hosting.autoresizingMask = [.minXMargin, .minYMargin]
        addSubview(hosting)
        controls = hosting
        setAccessibilityLabel("Reader")
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        web.frame = bounds
        controls?.frame.origin = NSPoint(x: bounds.maxX - 96 - 16, y: bounds.maxY - 34 - 16)
    }

    func focus() { window?.makeFirstResponder(web) }
    override func cancelOperation(_ sender: Any?) { onClose() }

    private func applyStyle() {
        web.evaluateJavaScript(ReaderDocument.script(ReaderStyle(state.browserPreferences), dark: state.isDark), completionHandler: nil)
    }

    // The article's links open in the page's own tab, never inside the reader.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard action.navigationType == .linkActivated, let url = action.request.url else { return .allow }
        if ["http", "https"].contains(url.scheme?.lowercased() ?? "") { onOpen(url) }
        return .cancel
    }
}

/// "Aa" (font, size, theme) and close, as a small pill over the article.
private struct ReaderControls: View {
    let state: BrowserState
    let apply: () -> Void
    let close: () -> Void

    var body: some View {
        let colors = state.palette
        let style = ReaderStyle(state.browserPreferences)
        HStack(spacing: 2) {
            Menu {
                Picker("Font", selection: Binding(get: { style.font }, set: { state.browserPreferences.readerFont = $0.rawValue; apply() })) {
                    ForEach(ReaderStyle.Font.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Theme", selection: Binding(get: { style.theme }, set: { state.browserPreferences.readerTheme = $0.rawValue; apply() })) {
                    ForEach(ReaderStyle.Theme.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Divider()
                Button("Larger Text") { resize(1) }.disabled(style.size >= ReaderStyle.sizes.upperBound)
                Button("Smaller Text") { resize(-1) }.disabled(style.size <= ReaderStyle.sizes.lowerBound)
            } label: {
                Image(systemName: "textformat.size").font(.system(size: 13, weight: .medium)).frame(width: 30, height: 28)
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            .help("Reader appearance")
            ChromeButton(symbol: "xmark", help: "Close Reader", colors: colors, size: 28, glass: false, action: close)
        }
        .padding(3)
        .foregroundStyle(colors.text)
        .modalSurface(colors, radius: 17)
        .frame(width: 96, height: 34)
    }

    private func resize(_ step: Int) {
        state.browserPreferences.readerSize = ReaderStyle(state.browserPreferences).size + step
        apply()
    }
}
