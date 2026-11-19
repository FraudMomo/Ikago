import AppKit

/// Where the password key stands on a Chromium page.
struct PasswordKeyState {
    /// The document generation that has the key, its isolated world, and whether an injection is under way.
    var injectedGeneration = -1
    var context: Int?
    var injecting = false
    var monitor: Any?
    /// Same-site child frames (a sign-in iframe) with the script: frame ID → isolated world.
    var frames: [String: Int] = [:]
    var framesScanned = Date.distantPast
    /// Whether this document's site has a saved login, so the key may show.
    var keyAllowed = false
    /// A sign-in waiting for its page to confirm it (`CEFWebTab+PasswordSaving`).
    var saveWatch: Task<Void, Never>?
}

/// The password key on Chromium. The key script runs in the "ikago-passwords" isolated world of the top document and
/// its same-site frames, on sites with a saved login or, while saving is on, any HTTPS site (the key shows only with a
/// saved login), so pages can't see its code. The page never talks to Ikago: Ikago watches the real clicks and keys on
/// the page and then asks the script what happened. Nothing turns on DevTools' Runtime events, which pages can sometimes detect
/// and which would send every console message to Ikago.
extension CEFWebTab {
    static let passwordWorld = "ikago-passwords"

    var hasPasswordKey: Bool { passwordKeyState.injectedGeneration == documentGeneration && passwordKeyState.context != nil }

    /// Once per document, after it commits; retried briefly while a page is still redirecting, because a
    /// navigation cancels DevTools commands in flight.
    /// Whether this page gets the script: a saved login to fill, sign-ins to watch for saving, or new-password fields.
    var watchesPasswords: Bool {
        let url = URL(string: currentURL)
        return PasswordChooser.offers(for: url, onChromium: true) || (!isPrivatePage && PasswordSaving.watches(url, onChromium: true))
            || PasswordChooser.offersStrongPasswords(for: url, isPrivate: isPrivatePage)
    }

    var isPrivatePage: Bool { profileID.hasPrefix("Private-") }

    /// Whether this page's new-password fields offer a strong password.
    var offersStrongPasswords: Bool { PasswordChooser.offersStrongPasswords(for: URL(string: currentURL), isPrivate: isPrivatePage) }

    func injectPasswordKey() {
        if hasPasswordKey { return scanPasswordFrames() }
        guard !isTornDown, !passwordKeyState.injecting, watchesPasswords else { return }
        passwordKeyState.injecting = true
        installPasswordMonitor()
        Task { @MainActor in
            defer { passwordKeyState.injecting = false }
            // Always the current document: a commit that arrives meanwhile is picked up by the next try.
            for _ in 0..<15 where !isTornDown && !hasPasswordKey && watchesPasswords {
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
                    passwordKeyState.frames = [:]
                    passwordKeyState.keyAllowed = PasswordChooser.offers(for: URL(string: currentURL), onChromium: true)
                    _ = await passwordCall(context, "function (allowed, strong) { window.__ikagoPasswordKey.setKeyAllowed(allowed); window.__ikagoPasswordKey.setGenerateAllowed(strong) }",
                                           [passwordKeyState.keyAllowed, offersStrongPasswords], generation: generation)
                    scanPasswordFrames(force: true)
                } catch {
                    #if IKAGO_CHECKS
                    print("CEF_PASSWORDS_INJECT_RETRY \(error.localizedDescription)")
                    #endif
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
        }
    }

    /// One passive monitor per tab that has ever had the script. It never changes or swallows a click or key.
    private func installPasswordMonitor() {
        guard passwordKeyState.monitor == nil else { return }
        passwordKeyState.monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .keyDown, .keyUp]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, self.hasPasswordKey, let window = self.page.window, event.window === window else { return }
                switch event.type {
                case .keyUp, .keyDown:
                    guard let responder = window.firstResponder as? NSView, responder === self.page || responder.isDescendant(of: self.page) else { return }
                    if event.type == .keyDown, [36, 76].contains(event.keyCode) { self.checkForSignIn() }
                    // Tab into a field: list the logins once focus has landed.
                    if event.type == .keyUp, event.keyCode == 48, PasswordChooser.suggestsOnFocus { self.suggestAtFocusedField() }
                default:
                    guard let hit = window.contentView?.hitTest(event.locationInWindow), hit === self.page || hit.isDescendant(of: self.page) else { return }
                    if event.type == .leftMouseUp { return self.passwordMouseUp() }
                    guard event.clickCount == 1,
                          event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock).isEmpty else { return }
                    self.passwordKeyClicked(at: self.page.convert(event.locationInWindow, from: nil))
                }
            }
            return event
        }
    }

    func removePasswordMonitor() {
        if let monitor = passwordKeyState.monitor { NSEvent.removeMonitor(monitor) }
        passwordKeyState.monitor = nil
    }

    private var cssZoom: CGFloat { pow(1.2, zoomLevel) }

    /// A CSS rect from the key script, in the page view's coordinates (the view isn't flipped).
    func fieldRect(_ value: Any?, offset: CGPoint = .zero) -> NSRect? {
        guard let rect = value as? [String: Any], let left = rect["x"] as? Double, let top = rect["y"] as? Double,
              let width = rect["width"] as? Double, let height = rect["height"] as? Double else { return nil }
        let zoom = cssZoom, x = left + offset.x, y = top + offset.y
        return NSRect(x: x * zoom, y: page.bounds.height - page.topInset - (y + height) * zoom, width: width * zoom, height: height * zoom)
    }

    /// A real click at `point` in the page view: on the key, list the logins; elsewhere, list them if it focused a
    /// sign-in field and Ikago suggests on focus.
    func passwordKeyClicked(at point: NSPoint) {
        guard hasPasswordKey, let context = passwordKeyState.context else { return }
        // The web contents sit below the top inset; CSS pixels are points divided by the zoom factor.
        let x = point.x / cssZoom, y = (page.bounds.height - page.topInset - point.y) / cssZoom
        guard x >= 0, y >= 0 else { return }
        let generation = documentGeneration
        Task { @MainActor in
            let result = try? await devTools("Runtime.callFunctionOn", [
                "functionDeclaration": "function (x, y) { return window.__ikagoPasswordKey.hit(x, y) }",
                "executionContextId": context, "arguments": [["value": x], ["value": y]], "returnByValue": true],
                generation: generation)
            let value = (result?["result"] as? [String: Any])?["value"]
            if let rect = value as? [String: Any] { return await fillFromVault(field: fieldRect(rect), generation: generation, report: rect) }
            if PasswordChooser.suggestsOnFocus { suggestAtFocusedField() }
        }
    }

    /// Lists logins under the focused field, if the key is showing in one.
    func suggestAtFocusedField() {
        guard hasPasswordKey, let context = passwordKeyState.context else { return }
        let generation = documentGeneration
        Task { @MainActor in
            // Focus and the key settle first; a busy page takes longer to handle the click, so look a few times.
            for delay in [60, 140, 300] {
                try? await Task.sleep(for: .milliseconds(delay))
                guard generation == documentGeneration else { return }
                let result = try? await devTools("Runtime.callFunctionOn", [
                    "functionDeclaration": "function () { return window.__ikagoPasswordKey.focusRect() }",
                    "executionContextId": context, "returnByValue": true], generation: generation)
                if let rect = (result?["result"] as? [String: Any])?["value"] as? [String: Any] {
                    return await fillFromVault(field: fieldRect(rect), generation: generation, report: rect)
                }
            }
        }
    }

    /// `report` is what the key script said about the field; a new-password field gets a strong password instead.
    func fillFromVault(field: NSRect?, generation: Int, context frameContext: Int? = nil, origin frameOrigin: String? = nil,
                       report: [String: Any]? = nil) async {
        if report?["newPassword"] as? Bool == true {
            return await suggestStrong(field: field, generation: generation, context: frameContext, origin: frameOrigin,
                                       rules: PasswordGenerator.Rules(report?["rules"] as? [String: Any]))
        }
        guard let context = frameContext ?? passwordKeyState.context, let url = URL(string: currentURL),
              let login = await PasswordChooser.choose(for: url, in: page, field: field, typed: report?["typed"] as? String ?? "",
                                                       readTyped: { [weak self] in
                                                           guard let self, generation == self.documentGeneration else { return nil }
                                                           return await self.passwordCall(context, "function () { return window.__ikagoPasswordKey.typed() }",
                                                                                          generation: generation) as? String
                                                       }),
              generation == documentGeneration, currentURL == url.absoluteString else { return }
        // The login travels as call arguments, never as script text.
        _ = try? await devTools("Runtime.callFunctionOn", [
            "functionDeclaration": "function (username, password, origin) { return window.__ikagoPasswordKey.fill(username, password, origin) }",
            "executionContextId": context,
            "arguments": [["value": login.username], ["value": login.password], ["value": frameOrigin ?? PasswordChooser.origin(of: url)]],
            "returnByValue": true, "userGesture": false], generation: generation)
        #if IKAGO_CHECKS
        print("CEF_PASSWORDS_FILLED")
        #endif
    }

    /// A strong password for a new-password field: filled into it and its confirmation, then saved at once with the
    /// username the form already has (the arguments carry it, never script text).
    private func suggestStrong(field: NSRect?, generation: Int, context frameContext: Int?, origin frameOrigin: String?,
                               rules: PasswordGenerator.Rules) async {
        guard let context = frameContext ?? passwordKeyState.context, let url = URL(string: currentURL),
              let choice = await PasswordChooser.chooseNew(for: url, in: page, field: field, rules: rules, isPrivate: isPrivatePage),
              generation == documentGeneration, currentURL == url.absoluteString else { return }
        let origin = frameOrigin ?? PasswordChooser.origin(of: url)
        switch choice {
        case .generated(let password):
            let result = try? await devTools("Runtime.callFunctionOn", [
                "functionDeclaration": "function (password, origin) { return window.__ikagoPasswordKey.fillNew(password, origin) }",
                "executionContextId": context, "arguments": [["value": password], ["value": origin]],
                "returnByValue": true, "userGesture": false], generation: generation)
            guard let filled = (result?["result"] as? [String: Any])?["value"] as? [String: Any] else { return }
            if filled["filled"] as? Int ?? 0 > 0 { PasswordChooser.rememberStrong(password, host: URL(string: origin)?.host ?? url.host ?? "") }
            #if IKAGO_CHECKS
            print("CEF_PASSWORDS_STRONG_FILLED \(filled["filled"] as? Int ?? 0)")
            #endif
        case .login(let username, let password):
            _ = try? await devTools("Runtime.callFunctionOn", [
                "functionDeclaration": "function (username, password, origin) { return window.__ikagoPasswordKey.fill(username, password, origin) }",
                "executionContextId": context, "arguments": [["value": username], ["value": password], ["value": origin]],
                "returnByValue": true, "userGesture": false], generation: generation)
        }
    }
}
