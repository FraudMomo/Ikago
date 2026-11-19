import AppKit
import Foundation

// MARK: - Scripts
extension CEFWebTab {
    /// Every evaluation targets an explicitly created isolated world. No fallback
    /// to the page world, user gesture synthesis or universal origin access.
    func evaluate(_ script: String) async throws -> Any? { try await isolated(script) }
    func callAsync(_ body: String) async throws -> Any? {
        try await isolated("(async () => {\n\(body)\n})()")
    }
    private func isolated(_ expression: String) async throws -> Any? {
        let generation = documentGeneration
        let context = try await browserContext(generation: generation)
        let result: [String: Any]
        do {
            result = try await command("Runtime.evaluate", [
                "expression": expression, "contextId": context, "returnByValue": true,
                "awaitPromise": true, "userGesture": false
            ], generation: generation)
        } catch {
            // The world may be gone (a crash, or a navigation Ikago didn't see): create it afresh next time.
            if browserWorld?.context == context { browserWorld = nil }
            throw error
        }
        if result["exceptionDetails"] != nil { throw CEFError.script("The browser script failed in this page.") }
        guard let value = result["result"] as? [String: Any] else { throw CEFError.noResult }
        if value["type"] as? String == "undefined" || value["subtype"] as? String == "null" { return nil }
        if value["unserializableValue"] != nil { throw CEFError.noResult }
        guard let decoded = value["value"] else { throw CEFError.noResult }
        return decoded
    }
    /// The document's isolated world, created once per document generation.
    private func browserContext(generation: Int) async throws -> Int {
        if let world = browserWorld, world.generation == generation { return world.context }
        let tree = try await command("Page.getFrameTree", [:], generation: generation)
        guard let frameTree = tree["frameTree"] as? [String: Any],
              let frame = frameTree["frame"] as? [String: Any], let frameID = frame["id"] as? String else {
            throw CEFError.noResult
        }
        let world = try await command("Page.createIsolatedWorld", ["frameId": frameID, "worldName": "ikago-browser"], generation: generation)
        guard let context = world["executionContextId"] as? Int else { throw CEFError.noResult }
        browserWorld = (generation, context)
        return context
    }
    func snapshot() async throws -> NSImage {
        try await snapshot(rect: NSRect(origin: .zero, size: page.bounds.size))
    }
    func snapshot(rect: NSRect) async throws -> NSImage {
        guard rect.origin.x.isFinite, rect.origin.y.isFinite, rect.width.isFinite, rect.height.isFinite,
              rect.origin.x >= 0, rect.origin.y >= 0, rect.width > 0, rect.height > 0 else {
            throw CEFError.noResult
        }
        let result = try await command("Page.captureScreenshot", ["format": "png", "captureBeyondViewport": false,
            "clip": ["x": rect.origin.x, "y": rect.origin.y, "width": rect.width, "height": rect.height, "scale": 1]
        ], generation: documentGeneration)
        guard let encoded = result["data"] as? String, let data = Data(base64Encoded: encoded),
              let image = NSImage(data: data) else { throw CEFError.noResult }
        return image
    }
    /// A DevTools command for this page. With `generation`, it fails once the page navigates.
    func devTools(_ method: String, _ parameters: [String: Any], generation: Int? = nil) async throws -> [String: Any] {
        try await command(method, parameters, generation: generation)
    }
    private func command(_ method: String, _ parameters: [String: Any], generation: Int?) async throws -> [String: Any] {
        guard !isTornDown else { throw CEFError.closed }
        let data: Data = try await withCheckedThrowingContinuation { continuation in
            page.devToolsMethod(method, parameters: parameters) { result, error in
                if let error { continuation.resume(throwing: error) }
                else if let result {
                    do { continuation.resume(returning: try JSONSerialization.data(withJSONObject: result)) }
                    catch { continuation.resume(throwing: error) }
                }
                else { continuation.resume(throwing: CEFError.noResult) }
            }
        }
        guard !isTornDown, generation == nil || generation == documentGeneration else { throw CEFError.closed }
        guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw CEFError.noResult }
        return result
    }
}

// MARK: - Saving
extension CEFWebTab {
    /// Every Save Page format: MHTML from DevTools' snapshot, the HTML or text from the page, Chromium's own PDFs, and
    /// images from DevTools' screenshots (the full page beyond the viewport, or what is on screen).
    func exportPage(_ format: PageSaveFormat) async throws -> Data {
        switch format {
        case .archive:
            let result = try await devTools("Page.captureSnapshot", ["format": "mhtml"], generation: documentGeneration)
            return try PageExport.string(result["data"])
        case .html: return try PageExport.string(try await evaluate(PageExport.htmlScript))
        case .text: return try PageExport.string(try await evaluate(PageExport.textScript))
        case .pdf, .longPDF:
            // Chromium's own print (headful DevTools can't print): letter pages, or one page the document's size (CSS
            // pixels at 96 per inch, a hair taller so nothing spills onto a second page).
            let inches = format == .longPDF ? try await contentSize().applying(CGAffineTransform(scaleX: 1 / 96, y: 1 / 96)) : nil
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
            defer { try? FileManager.default.removeItem(at: file) }
            let ok: Bool = await withCheckedContinuation { continuation in
                if let inches {
                    page.saveLongPDF(to: file.path, inches: CGSize(width: inches.width, height: inches.height + 0.05)) {
                        continuation.resume(returning: $0)
                    }
                } else {
                    page.savePDF(to: file.path) { continuation.resume(returning: $0) }
                }
            }
            guard ok else { throw PageSaveError.failed }
            return try Data(contentsOf: file)
        case .fullPNG, .fullJPEG:
            let size = try await contentSize()
            let height = min(size.height, PageExport.longestImage)
            var parameters: [String: Any] = ["format": format.isJPEG ? "jpeg" : "png", "captureBeyondViewport": true,
                                             "clip": ["x": 0, "y": 0, "width": size.width, "height": height, "scale": 1]]
            if format.isJPEG { parameters["quality"] = 90 }
            return try decode(try await devTools("Page.captureScreenshot", parameters, generation: documentGeneration))
        case .visiblePNG, .visibleJPEG:
            return try PageExport.encode(try await snapshot(), jpeg: format.isJPEG)
        }
    }

    /// The whole document's size in CSS pixels.
    private func contentSize() async throws -> CGSize {
        let metrics = try await devTools("Page.getLayoutMetrics", [:], generation: documentGeneration)
        guard let content = metrics["cssContentSize"] as? [String: Any], let width = content["width"] as? Double,
              let height = content["height"] as? Double, width > 0, height > 0 else { throw PageSaveError.failed }
        return CGSize(width: width, height: height)
    }

    private func decode(_ result: [String: Any]) throws -> Data {
        guard let encoded = result["data"] as? String, let data = Data(base64Encoded: encoded) else { throw PageSaveError.failed }
        return data
    }
}
