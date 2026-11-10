import AppKit

/// Where the password key stands on a Chromium page.
struct PasswordKeyState {
    /// The document generation that has the key, its isolated world, and whether an injection is under way.
    var injectedGeneration = -1
    var context: Int?
    var injecting = false
    var monitor: Any?
}

/// The password key on Chromium. The key script runs in the "ikago-passwords" isolated world of top-level
/// documents whose site has a saved login, so pages can't see its code, and other sites get nothing at all.
/// The page never talks to Ikago: Ikago watches the real mouse clicks on the page and asks the script whether
/// one landed on the key. Nothing turns on DevTools' Runtime events, which pages can sometimes detect
/// and which would send every console message to Ikago.
extension CEFWebTab {
    static let passwordWorld = "ikago-passwords"

    var hasPasswordKey: Bool { passwordKeyState.injectedGeneration == documentGeneration && passwordKeyState.context != nil }

    /// Once per document, after it commits; retried briefly while a page is still redirecting, because a
    /// navigation cancels DevTools commands in flight.
    func injectPasswordKey() {
        guard !isTornDown, !hasPasswordKey, !passwordKeyState.injecting,
              PasswordChooser.offers(for: URL(string: currentURL), onChromium: true) else { return }
        passwordKeyState.injecting = true
        installPasswordMonitor()
        Task { @MainActor in
            defer { passwordKeyState.injecting = false }
            // Always the current document: a commit that arrives meanwhile is picked up by the next try.
            for _ in 0..<15 where !isTornDown && !hasPasswordKey && PasswordChooser.offers(for: URL(string: currentURL), onChromium: true) {
                let generation = documentGeneration
                do {
                    let tree = try await devTools("Page.getFrameTree", [:], generation: generation)
                    guard let frame = (tree["frameTree"] as? [String: Any])?["frame"] as? [String: Any],
                          let frameID = frame["id"] as? String else { throw CEFError.noResult }
                    let world = try await devTools("Page.createIsolatedWorld", ["frameId": frameID, "worldName": Self.passwordWorld], generation: generation)
                    guard let context = world["executionContextId"] as? Int else { throw CEFError.noResult }
                    _ = try await devTools("Runtime.evaluate", ["expression": PasswordKeyScript.chromium,
                                                                "contextId": context, "userGesture": false], generation: generation)
                    passwordKeyState.context = context
                    passwordKeyState.injectedGeneration = generation
                } catch {
                    #if IKAGO_CHECKS
                    print("CEF_PASSWORDS_INJECT_RETRY \(error.localizedDescription)")
                    #endif
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
        }
    }

    /// One passive monitor per tab that has ever shown the key. It never changes or swallows the click.
    private func installPasswordMonitor() {
        guard passwordKeyState.monitor == nil else { return }
        passwordKeyState.monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, self.hasPasswordKey, event.window === self.page.window, event.clickCount == 1,
                      event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock).isEmpty,
                      let hit = self.page.window?.contentView?.hitTest(event.locationInWindow),
                      hit === self.page || hit.isDescendant(of: self.page) else { return }
                self.passwordKeyClicked(at: self.page.convert(event.locationInWindow, from: nil))
            }
            return event
        }
    }

    func removePasswordMonitor() {
        if let monitor = passwordKeyState.monitor { NSEvent.removeMonitor(monitor) }
        passwordKeyState.monitor = nil
    }

    /// A real click at `point` in the page view: if the key is there, pick a login and fill it.
    func passwordKeyClicked(at point: NSPoint) {
        guard hasPasswordKey, let context = passwordKeyState.context, let url = URL(string: currentURL) else { return }
        // The web contents sit below the top inset; CSS pixels are points divided by the zoom factor.
        let zoom = pow(1.2, zoomLevel)
        let x = point.x / zoom, y = (page.bounds.height - page.topInset - point.y) / zoom
        guard x >= 0, y >= 0 else { return }
        let generation = documentGeneration
        Task { @MainActor in
            let result = try? await devTools("Runtime.callFunctionOn", [
                "functionDeclaration": "function (x, y) { return window.__ikagoPasswordKey.hit(x, y) }",
                "executionContextId": context, "arguments": [["value": x], ["value": y]], "returnByValue": true],
                generation: generation)
            guard (result?["result"] as? [String: Any])?["value"] as? Bool == true, generation == documentGeneration,
                  let login = await PasswordChooser.choose(for: url, in: page),
                  generation == documentGeneration, currentURL == url.absoluteString else { return }
            // The login travels as call arguments, never as script text.
            _ = try? await devTools("Runtime.callFunctionOn", [
                "functionDeclaration": "function (username, password, origin) { return window.__ikagoPasswordKey.fill(username, password, origin) }",
                "executionContextId": context,
                "arguments": [["value": login.username], ["value": login.password], ["value": PasswordChooser.origin(of: url)]],
                "returnByValue": true, "userGesture": false], generation: generation)
            #if IKAGO_CHECKS
            print("CEF_PASSWORDS_FILLED")
            #endif
        }
    }
}
