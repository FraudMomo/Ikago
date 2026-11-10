import AppKit

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
