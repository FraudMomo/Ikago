import AppKit
import WebKit
import PDFKit

// MARK: - Safety
/// Guards against pages abusing the browser: opening other apps, dialog loops, crash loops.
extension WebKitTab {
    /// Direct links, sign-in redirects and scripted app handoffs share one confirmed route.
    func openExternal(_ url: URL, from frame: WKFrameInfo?) async {
        let host = frame?.securityOrigin.host ?? webView.url?.host ?? ""
        await externalLinks.open(url, sourceHost: host, in: webView.window)
    }

    /// A page may not open itself as a top-level data: document (a common phishing trick).
    /// Images are fine, except SVG, which is a scriptable document.
    static func blocksTopLevelData(_ url: URL, action: WKNavigationAction) -> Bool {
        guard action.targetFrame?.isMainFrame ?? true else { return false }
        return isBlockedDataDocument(url)
    }

    static func isBlockedDataDocument(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "data" else { return false }
        let text = url.absoluteString.lowercased()
        return !text.hasPrefix("data:image/") || text.hasPrefix("data:image/svg")
    }

    /// The web content process died. Reload once; if it dies again soon, stop and say so
    /// instead of looping.
    func recoverFromCrash() {
        if let last = lastCrash, Date().timeIntervalSince(last) < 30 {
            delegate?.webTab(self, didFailLoad: "This page stopped working again, so Ikago didn’t reload it.", url: currentURL)
            return
        }
        lastCrash = Date()
        webView.reload()
    }
}

// MARK: - Session history

extension WebKitTab {
    /// WebKit's own record of the tab (Back and Forward, scroll positions), when small enough, and the Back addresses.
    func sessionHistory() async -> TabHistory? {
        var history = TabHistory(back: TabHistory.trimmed(webView.backForwardList.backList.map(\.url.absoluteString)))
        if let data = webView.interactionState as? Data, data.count <= TabHistory.maxState { history.state = data.base64EncodedString() }
        return history.isEmpty ? nil : history
    }

    func restoreHistory(_ history: TabHistory) -> Bool {
        guard let state = history.state, let data = Data(base64Encoded: state) else { return false }
        webView.interactionState = data
        return true
    }
}

// MARK: - Media
extension WebKitTab {
    func pauseForHistory() { webView.pauseAllMediaPlayback {} }
    func hasNavigationHistory() async -> Bool {
        !webView.backForwardList.backList.isEmpty || !webView.backForwardList.forwardList.isEmpty
    }
    func controlMedia(_ action: MediaPlaybackAction) async {
        // Embedded players can live in cross-origin frames. Use the exact frames which
        // reported playback, rather than evaluating only in the main document.
        let entries = audibleFrames.filter { $0.value.playback.available }
        for (document, entry) in entries where action == .pause || entry.playback.playing || !entries.values.contains(where: { $0.playback.playing }) {
            do {
                if let report = try await webView.callAsyncJavaScript(MediaPlaybackScript.control(action), arguments: [:],
                    in: entry.frame.isMainFrame ? nil : entry.frame, contentWorld: .defaultClient) as? [String: Any] {
                    frameReportedAudio(report["audible"] as? Bool ?? false,
                                       playback: MediaPlaybackState(report), frame: entry.frame, document: document)
                }
            } catch {
                #if DEBUG
                print("IKTEST media control failed code=\((error as NSError).code) main=\(entry.frame.isMainFrame)")
                #endif
            }
            if action != .pause { break }
        }
    }
}

// MARK: - Saving
extension WebKitTab {
    /// Every Save Page format: WebKit's own web archive (every resource), the HTML or text from the page, PDFs WebKit
    /// draws, and images from those or from a snapshot.
    func exportPage(_ format: PageSaveFormat) async throws -> Data {
        switch format {
        case .archive:
            return try await withCheckedThrowingContinuation { continuation in
                webView.createWebArchiveData { result in continuation.resume(with: result) }
            }
        case .html: return try PageExport.string(try await evaluate(PageExport.htmlScript))
        case .text: return try PageExport.string(try await evaluate(PageExport.textScript))
        case .pdf: return try await pagedPDF()
        case .longPDF: return try await longPDF()
        case .fullPNG, .fullJPEG: return try PageExport.encode(try PageExport.rasterize(pdf: try await longPDF()), jpeg: format.isJPEG)
        case .visiblePNG, .visibleJPEG: return try PageExport.encode(try await snapshot(), jpeg: format.isJPEG)
        }
    }

    /// The whole page as one long PDF page: with no rect, WebKit draws all of its content.
    private func longPDF() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            webView.createPDF(configuration: WKPDFConfiguration()) { continuation.resume(with: $0) }
        }
    }

    /// The document in letter-shaped pages: WebKit draws each slice of the page as it is laid out, and the slices are
    /// joined into one PDF (a print operation can't run without its sheet).
    private func pagedPDF() async throws -> Data {
        let size = try await evaluate(PageExport.sizeScript) as? [Double] ?? []
        guard size.count == 2, size[0] > 0, size[1] > 0 else { throw PageSaveError.failed }
        let width = min(size[0], 2400), height = min(size[1], 60 * width * 11 / 8.5)
        let pageHeight = width * 11 / 8.5
        let document = PDFDocument()
        var top = 0.0
        while top < height {
            let configuration = WKPDFConfiguration()
            configuration.rect = CGRect(x: 0, y: top, width: width, height: min(pageHeight, height - top))
            let data: Data = try await withCheckedThrowingContinuation { continuation in
                webView.createPDF(configuration: configuration) { continuation.resume(with: $0) }
            }
            if let page = PDFDocument(data: data)?.page(at: 0) { document.insert(page, at: document.pageCount) }
            top += pageHeight
        }
        guard let data = document.dataRepresentation(), document.pageCount > 0 else { throw PageSaveError.failed }
        return data
    }
}
