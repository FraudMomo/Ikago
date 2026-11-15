import AppKit

extension TabController {
    var isReading: Bool { reader != nil }

    /// Shows the page's article in the reader, or closes the reader.
    func toggleReader() {
        if reader != nil { return closeReader() }
        guard let page, let state = browserState, AddressResolver.isWebURL(page.currentURL) else { return }
        let generation = tab.url
        Task { @MainActor [weak self] in
            let article = ReaderArticle(try? await page.evaluate(ReaderScript.extract))
            guard let self, self.reader == nil, self.page === page, self.tab.url == generation else { return }
            let overlay = ReaderOverlay(article: article, state: state)
            overlay.frame = self.hostView.bounds
            overlay.onClose = { [weak self] in self?.closeReader() }
            overlay.onOpen = { [weak self] url in
                self?.closeReader()
                (self?.host as? BrowserCommands)?.openInNewTab(url.absoluteString)
            }
            self.hostView.addSubview(overlay, positioned: .above, relativeTo: nil)
            self.reader = overlay
            overlay.focus()
        }
    }

    func closeReader() {
        guard let overlay = reader else { return }
        overlay.removeFromSuperview()
        reader = nil
        page?.focus()
    }
}
