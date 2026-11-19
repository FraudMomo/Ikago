import AppKit

/// Sign-in frames and saving on Chromium. Same-site child frames get the key script too (a sign-in iframe such as
/// idmsa.apple.com inside appstoreconnect.apple.com), and after a real click or Return Ikago asks each frame whether
/// the key was clicked or a sign-in happened. A sign-in is offered once its page confirms it: the password field went
/// away, or the page moved on to one that doesn't ask for a password again.
extension CEFWebTab {
    /// Calls a function in one of the script's isolated worlds; nil when it failed (the frame went away).
    func passwordCall(_ context: Int, _ function: String, _ arguments: [Any] = [], generation: Int) async -> Any? {
        guard let result = try? await devTools("Runtime.callFunctionOn", [
            "functionDeclaration": function, "executionContextId": context,
            "arguments": arguments.map { ["value": $0] }, "returnByValue": true], generation: generation) else { return nil }
        return (result["result"] as? [String: Any])?["value"] ?? NSNull()
    }

    /// Finds same-site HTTPS child frames that don't have the script yet. Frames often load after the page (a sign-in
    /// iframe inserted by script), so this runs again after loads and clicks, at most every 1.5 seconds.
    func scanPasswordFrames(force: Bool = false) {
        guard hasPasswordKey, force || Date().timeIntervalSince(passwordKeyState.framesScanned) > 1.5,
              let top = URL(string: currentURL)?.host else { return }
        passwordKeyState.framesScanned = Date()
        let generation = documentGeneration, site = PublicSuffix.registrableDomain(PasswordVault.site(top))
        Task { @MainActor in
            guard let tree = try? await devTools("Page.getFrameTree", [:], generation: generation),
                  let root = tree["frameTree"] as? [String: Any] else { return }
            var found: [(id: String, url: URL)] = []
            func walk(_ node: [String: Any]) {
                for child in node["childFrames"] as? [[String: Any]] ?? [] {
                    if let frame = child["frame"] as? [String: Any], let id = frame["id"] as? String,
                       let url = (frame["url"] as? String).flatMap(URL.init(string:)), url.scheme == "https", let host = url.host,
                       PublicSuffix.registrableDomain(PasswordVault.site(host)) == site { found.append((id, url)) }
                    walk(child)
                }
            }
            walk(root)
            for frame in found where passwordKeyState.frames[frame.id] == nil && generation == documentGeneration {
                guard let world = try? await devTools("Page.createIsolatedWorld", ["frameId": frame.id, "worldName": Self.passwordWorld], generation: generation),
                      let context = world["executionContextId"] as? Int,
                      (try? await devTools("Runtime.evaluate", ["expression": Self.pageScripts, "contextId": context, "userGesture": false],
                                           generation: generation)) != nil else { continue }
                _ = await passwordCall(context, "function (allowed, strong) { window.__ikagoPasswordKey.setKeyAllowed(allowed); window.__ikagoPasswordKey.setGenerateAllowed(strong) }",
                                       [passwordKeyState.keyAllowed, offersStrongPasswords], generation: generation)
                passwordKeyState.frames[frame.id] = context
            }
        }
    }

    /// After a real click: the key in a sign-in frame, the logins under a focused field there, and sign-ins anywhere.
    func passwordMouseUp() {
        let generation = documentGeneration
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))  // the click reaches the page first
            guard generation == documentGeneration else { return }
            for (frameID, context) in passwordKeyState.frames {
                let result = await passwordCall(context, "function () { return window.__ikagoPasswordKey.poll() }", generation: generation)
                guard result != nil else { passwordKeyState.frames[frameID] = nil; continue }  // re-injected on the next scan
                var rect = (result as? [String: Any])?["key"]
                if rect == nil, PasswordChooser.suggestsOnFocus {
                    rect = await passwordCall(context, "function () { return window.__ikagoPasswordKey.focusRect() }", generation: generation)
                }
                guard let css = rect as? [String: Any] else { continue }
                let offset = await frameOffset(frameID, generation: generation)
                let origin = await passwordCall(context, "function () { return location.origin }", generation: generation) as? String
                await fillFromVault(field: offset.flatMap { fieldRect(css, offset: $0) }, generation: generation, context: context,
                                    origin: origin, report: css)
                return
            }
            checkForSignIn(delay: false)
            scanPasswordFrames()
        }
    }

    /// Where a child frame's content starts in the top document, for placing the list under its field.
    private func frameOffset(_ frameID: String, generation: Int) async -> CGPoint? {
        guard let owner = try? await devTools("DOM.getFrameOwner", ["frameId": frameID], generation: generation),
              let node = owner["backendNodeId"] as? Int,
              let box = try? await devTools("DOM.getBoxModel", ["backendNodeId": node], generation: generation),
              let content = (box["model"] as? [String: Any])?["content"] as? [Double], content.count >= 2 else { return nil }
        return CGPoint(x: content[0], y: content[1])
    }

    /// Asks every frame for a sign-in after Return or a click, then follows it until the page confirms it.
    func checkForSignIn(delay: Bool = true) {
        guard PasswordSaving.isEnabled, !isPrivatePage else { return }
        let generation = documentGeneration
        Task { @MainActor in
            if delay { try? await Task.sleep(for: .milliseconds(150)) }
            guard generation == documentGeneration else { return }
            let contexts = (passwordKeyState.context.map { [$0] } ?? []) + Array(passwordKeyState.frames.values)
            for context in contexts {
                guard let state = await passwordCall(context, "function () { return window.__ikagoPasswordKey.saveState() }",
                                                     generation: generation) as? [String: Any],
                      let host = await passwordCall(context, "function () { return location.hostname }", generation: generation) as? String
                else { continue }
                follow(state, host: host, context: context, generation: generation)
                return
            }
        }
    }

    private func follow(_ state: [String: Any], host: String, context: Int, generation: Int) {
        guard let password = state["password"] as? String else { return }
        let username = state["username"] as? String ?? ""
        let pageURL = URL(string: currentURL)
        func offer() {
            PasswordSaving.submitted(username: username, password: password, host: host, pageURL: pageURL, isPrivate: isPrivatePage, in: page)
        }
        if state["confirmed"] as? Bool == true { return offer() }
        passwordKeyState.saveWatch?.cancel()
        passwordKeyState.saveWatch = Task { @MainActor in
            for _ in 0..<40 {
                try? await Task.sleep(for: .milliseconds(500))
                if Task.isCancelled || isTornDown { return }
                if documentGeneration != generation {
                    // A new page: wait for it, and offer only if it doesn't ask for a password again.
                    try? await Task.sleep(for: .seconds(2))
                    if let context = passwordKeyState.context, passwordKeyState.injectedGeneration == documentGeneration,
                       await passwordCall(context, "function () { return window.__ikagoPasswordKey.hasPasswordField() }",
                                          generation: documentGeneration) as? Bool == true { return }
                    return offer()
                }
                guard let current = await passwordCall(context, "function () { return window.__ikagoPasswordKey.saveState() }",
                                                       generation: generation) as? [String: Any] else { return }
                if current["confirmed"] as? Bool == true { return offer() }
            }
        }
    }
}
