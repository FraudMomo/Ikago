import AppKit
import WebKit

/// What an agent can do in Ikago, behind the MCP tools (`AgentTools`). An agent works in tabs of its own, in an "Agent"
/// group of the front window's Space, opened in the background: it never takes the active tab, the keyboard or the
/// pointer from the person, who can watch any of its tabs, pause it, stop it, or approve what needs approving
/// (`AgentActivity`). The person's own tabs are reachable only when they allow it (Settings ▸ Agents).
@MainActor
enum AgentBrowser {
    struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ text: String) { errorDescription = text }
    }

    private static var activity: AgentActivity { .shared }

    // MARK: Short tab names

    /// Agents name tabs "t1", "t2"… instead of Ikago's long ids: fewer tokens in every call.
    private static var aliases: [String: String] = [:]
    private static var nextAlias = 1

    static func alias(_ tabID: String) -> String {
        if let existing = aliases.first(where: { $0.value == tabID })?.key { return existing }
        let name = "t\(nextAlias)"
        nextAlias += 1
        aliases[name] = tabID
        return name
    }

    static func resolve(_ name: String) -> String { aliases[name] ?? name }
    static var usesOpenTabs: Bool { BrowserSecurity.shared.preferences.agentUsesOpenTabs == true }

    // MARK: Tabs

    static func window() throws -> BrowserWindowController {
        guard let window = BrowserWindows.frontmost else { throw Failure("Ikago has no window open.") }
        return window
    }

    /// The agent's tabs, and the person's too when they allow it: id, title, address and whose it is.
    static func listTabs() -> String {
        var lines: [String] = []
        for window in BrowserWindows.all where !window.state.isPrivate {
            for tab in window.state.tabs where activity.drives(tab.id) || (usesOpenTabs && !tab.isHibernating) {
                let mark = activity.drives(tab.id) ? "agent" : (tab.id == window.state.activeTabID ? "person's, active" : "person's")
                lines.append("\(alias(tab.id)) [\(mark)] \(tab.displayTitle) — \(tab.url)")
            }
        }
        if lines.isEmpty { return "No agent tabs yet. Open one with tab_open." + (usesOpenTabs ? "" : " (The person's own tabs aren't shared.)") }
        return lines.joined(separator: "\n")
    }

    /// A new tab in the background, in the Agent group, loaded before this returns.
    static func open(_ url: String) async throws -> String {
        let window = try window()
        guard let target = AddressResolver.isWebURL(url) ? url : URL(string: "https://" + url).map(\.absoluteString),
              AddressResolver.isWebURL(target) else { throw Failure("Agents open web pages only (http or https).") }
        let state = window.state
        guard let tab = state.newTab(url: target, select: false, folderID: agentGroup(in: state)) else {
            throw Failure("Ikago couldn't open another tab.")
        }
        activity.adopt(tab.id)
        activity.record("Opened \(target)")
        _ = try await controller(for: tab.id)
        await settle(tab.id)
        return tab.id
    }

    /// The person's tab, for an agent allowed to use open tabs; it then shows the agent bar like the agent's own.
    static func use(_ tabID: String) throws {
        guard usesOpenTabs, let window = BrowserWindows.owner(of: tabID), !window.state.isPrivate, window.state.tab(tabID) != nil else {
            throw Failure("That tab isn't one the agent may use.")
        }
        activity.adopt(tabID)
        activity.record("Started using a tab of yours")
    }

    static func close(_ tabID: String) throws {
        try check(tabID)
        guard let window = BrowserWindows.owner(of: tabID) else { return }
        activity.closed(tabID)
        window.state.closeTab(tabID)
        activity.record("Closed a tab")
    }

    /// The "Agent" group the agent's tabs open in, made once per Space.
    private static func agentGroup(in state: BrowserState) -> String {
        if let existing = state.spaceFolders.first(where: { $0.name == "Agent" && $0.tagValue == .purple }) { return existing.id }
        let folder = state.createFolder(named: "Agent")
        state.setFolderTag(folder.id, to: .purple)
        return folder.id
    }

    static func check(_ tabID: String) throws {
        guard activity.drives(tabID) else {
            throw Failure(BrowserWindows.owner(of: tabID) == nil ? "There is no tab \(tabID)."
                          : "The agent doesn't drive tab \(tabID): the person stopped it there, or it isn't the agent's. Use tab_open.")
        }
    }

    static func controller(for tabID: String) async throws -> TabController {
        guard let window = BrowserWindows.owner(of: tabID), let tab = window.state.tab(tabID),
              let controller = window.content.ensureController(for: tab) else { throw Failure("There is no tab \(tabID).") }
        if tab.isHibernating { tab.isHibernating = false }
        controller.startIfNeeded()
        for _ in 0..<100 where controller.page == nil { try? await Task.sleep(for: .milliseconds(50)) }
        guard controller.page != nil else { throw Failure("Tab \(tabID) has no page (it may show one of Ikago's own pages).") }
        return controller
    }

    /// The tab's page, once the person lets the agent continue there: every tool that touches a tab waits while it's paused.
    static func page(_ tabID: String) async throws -> WebTab {
        try check(tabID)
        guard await activity.waitIfPaused(tabID) else { throw Failure("The person stopped the agent on this tab.") }
        guard let page = try await controller(for: tabID).page else { throw Failure("Tab \(tabID) has no page.") }
        return page
    }

    /// Waits for the page to finish loading and its content to stop changing, for at most 10 seconds.
    static func settle(_ tabID: String) async {
        guard let tab = BrowserWindows.owner(of: tabID)?.state.tab(tabID) else { return }
        try? await Task.sleep(for: .milliseconds(250))
        for _ in 0..<100 where tab.isLoading { try? await Task.sleep(for: .milliseconds(100)) }
        try? await Task.sleep(for: .milliseconds(300))
    }

    // MARK: Pages

    /// Calls the page script (`AgentPageScript`), installing it in this document first if needed.
    static func call(_ page: WebTab, _ method: String, _ arguments: [String: Any] = [:]) async throws -> Any? {
        let data = try JSONSerialization.data(withJSONObject: arguments)
        let json = String(decoding: data, as: UTF8.self)
        do {
            return try await page.callAsync(AgentPageScript.install + "\nreturn window.__ikagoAgent.\(method)(\(json))")
        } catch {
            throw Failure("The page didn't answer (it may still be loading, or blocks scripts): \(error.localizedDescription)")
        }
    }

    static func text(_ value: Any?) throws -> String {
        if let dictionary = value as? [String: Any] {
            if let error = dictionary["error"] as? String { throw Failure(error) }
            if let text = dictionary["text"] as? String { return text }
        }
        return value as? String ?? ""
    }

    /// What an action would do, for the consequential-action check: a click, a key (Enter or Space can press a button or
    /// send a form), or a submit (type with submit).
    enum Intent {
        case click, submit, none
        case key(String)
    }

    /// One action on a tab: waits while paused, shows what it does, asks the person first when it would buy, pay, send,
    /// post, delete or submit a payment form (unless they let agents act without asking, or allowed it on this site), then
    /// returns what changed on the page.
    static func act(_ tabID: String, ref: String?, label: String, intent: Intent,
                    _ body: @MainActor (WebTab) async throws -> Void) async throws -> String {
        let page = try await page(tabID)
        if let ref { _ = try? await call(page, "highlight", ["ref": ref, "label": label]) }
        var arguments: [String: Any]
        switch intent {
        case .none: arguments = [:]
        case .click: arguments = ["action": "click"]
        case .submit: arguments = ["action": "submit"]
        case .key(let key): arguments = ["action": "key", "key": key]
        }
        if !arguments.isEmpty {
            if let ref { arguments["ref"] = ref }
            // A page that can't be judged (it didn't answer) is treated as consequential: the person decides.
            let verdict = (try? await call(page, "assess", arguments)) as? [String: Any]
            if verdict == nil || verdict?["risky"] as? Bool == true {
                let what = verdict?["what"] as? String ?? ""
                let host = verdict?["site"] as? String ?? URL(string: page.currentURL)?.host ?? ""
                let action = what.isEmpty ? label : "\(label): “\(what)”"
                guard await activity.approve(tabID, action: action, host: host) else {
                    throw Failure("The person didn't allow this. Don't try it another way; ask them instead.")
                }
            }
        }
        activity.begin(tabID, label)
        defer { activity.end(tabID) }
        try await body(page)
        await settle(tabID)
        return try text(try await call(page, "changes"))
    }

    // MARK: Input

    /// A click: real input on Chromium (at the element's centre, after scrolling it into view), the page's own events
    /// on WebKit.
    static func click(_ tabID: String, ref: String) async throws -> String {
        try await act(tabID, ref: ref, label: "Click", intent: .click) { page in
            let point = try await call(page, "point", ["ref": ref]) as? [String: Any] ?? [:]
            if let error = point["error"] as? String { throw Failure(error) }
            if point["disabled"] as? Bool == true { throw Failure("That control is disabled.") }
            if let chromium = page as? CEFWebTab, let x = point["x"] as? Double, let y = point["y"] as? Double, point["covered"] == nil || point["covered"] is NSNull {
                for (type, buttons) in [("mouseMoved", 0), ("mousePressed", 1), ("mouseReleased", 0)] {
                    _ = try await chromium.devTools("Input.dispatchMouseEvent", ["type": type, "x": x, "y": y, "button": type == "mouseMoved" ? "none" : "left",
                                                                                 "buttons": buttons, "clickCount": 1])
                }
            } else {
                _ = try text(try await call(page, "click", ["ref": ref]))
            }
        }
    }

    static func type(_ tabID: String, ref: String, text value: String, submit: Bool) async throws -> String {
        try await act(tabID, ref: ref, label: submit ? "Type and submit" : "Type", intent: submit ? .submit : .none) { page in
            let point = try await call(page, "point", ["ref": ref]) as? [String: Any] ?? [:]
            if let error = point["error"] as? String { throw Failure(error) }
            if let blocked = try await call(page, "keyBlocked", ["ref": ref, "key": "a"]) as? String { throw Failure(blocked) }
            if let chromium = page as? CEFWebTab {
                _ = try text(try await call(page, "focus", ["ref": ref]))
                _ = try await chromium.devTools("Input.dispatchKeyEvent", ["type": "rawKeyDown", "modifiers": 4, "key": "a", "code": "KeyA",
                                                                           "windowsVirtualKeyCode": 65, "commands": ["selectAll"]])
                _ = try await chromium.devTools("Input.insertText", ["text": value])
                if submit { try await key(chromium, "Enter") }
            } else {
                _ = try text(try await call(page, "type", ["ref": ref, "text": value, "submit": submit]))
            }
        }
    }

    static func select(_ tabID: String, ref: String, value: String) async throws -> String {
        try await act(tabID, ref: ref, label: "Choose", intent: .click) { page in _ = try text(try await call(page, "select", ["ref": ref, "value": value])) }
    }

    static func press(_ tabID: String, key name: String, ref: String?) async throws -> String {
        try await act(tabID, ref: ref, label: "Press \(name)", intent: .key(name)) { page in
            if let chromium = page as? CEFWebTab {
                if let ref { _ = try text(try await call(page, "focus", ["ref": ref])) }
                // Real keys type into whatever has focus: never into a password or card field.
                var check: [String: Any] = ["key": name]
                if let ref { check["ref"] = ref }
                if let blocked = try await call(page, "keyBlocked", check) as? String { throw Failure(blocked) }
                try await key(chromium, name)
            } else {
                var arguments: [String: Any] = ["key": name]
                if let ref { arguments["ref"] = ref }
                _ = try text(try await call(page, "press", arguments))
            }
        }
    }

    static func scroll(_ tabID: String, ref: String?, direction: String) async throws -> String {
        try await act(tabID, ref: nil, label: "Scroll", intent: .none) { page in
            var arguments: [String: Any] = ["direction": direction]
            if let ref { arguments["ref"] = ref }
            _ = try text(try await call(page, "scroll", arguments))
        }
    }

    private static let keys: [String: (code: String, keyCode: Int)] = [
        "Enter": ("Enter", 13), "Tab": ("Tab", 9), "Escape": ("Escape", 27), "Backspace": ("Backspace", 8), "Delete": ("Delete", 46),
        "ArrowUp": ("ArrowUp", 38), "ArrowDown": ("ArrowDown", 40), "ArrowLeft": ("ArrowLeft", 37), "ArrowRight": ("ArrowRight", 39),
        "PageUp": ("PageUp", 33), "PageDown": ("PageDown", 34), "Home": ("Home", 36), "End": ("End", 35), " ": ("Space", 32),
    ]

    private static func key(_ page: CEFWebTab, _ name: String) async throws {
        let known = keys[name] ?? (name.count == 1 ? (code: "Key" + name.uppercased(), keyCode: Int(name.uppercased().unicodeScalars.first!.value)) : nil)
        guard let known else { throw Failure("Unknown key \(name).") }
        var down: [String: Any] = ["type": "keyDown", "key": name, "code": known.code, "windowsVirtualKeyCode": known.keyCode]
        if name == "Enter" { down["text"] = "\r" } else if name.count == 1 { down["text"] = name }
        _ = try await page.devTools("Input.dispatchKeyEvent", down)
        _ = try await page.devTools("Input.dispatchKeyEvent", ["type": "keyUp", "key": name, "code": known.code, "windowsVirtualKeyCode": known.keyCode])
    }

    // MARK: Screenshots

    /// The visible part of the page, or one element, as a JPEG no wider than 1280 pixels.
    static func screenshot(_ tabID: String, ref: String?) async throws -> Data {
        let page = try await page(tabID)
        var rect: CGRect?
        if let ref {
            let point = try await call(page, "point", ["ref": ref]) as? [String: Any] ?? [:]
            if let error = point["error"] as? String { throw Failure(error) }
            if let x = point["x"] as? Double, let y = point["y"] as? Double, let width = point["width"] as? Double, let height = point["height"] as? Double {
                rect = CGRect(x: x - width / 2, y: y - height / 2, width: width, height: height).insetBy(dx: -8, dy: -8)
            }
        }
        activity.record(ref == nil ? "Took a screenshot" : "Took a screenshot of \(ref!)")
        if let chromium = page as? CEFWebTab {
            var parameters: [String: Any] = ["format": "jpeg", "quality": 70]
            if let rect { parameters["clip"] = ["x": max(0, rect.minX), "y": max(0, rect.minY), "width": rect.width, "height": rect.height, "scale": 1] }
            let result = try await chromium.devTools("Page.captureScreenshot", parameters)
            guard let encoded = result["data"] as? String, let data = Data(base64Encoded: encoded) else { throw Failure("No screenshot.") }
            return try shrink(data)
        }
        guard let webKit = page as? WebKitTab else { throw Failure("No screenshot.") }
        let configuration = WKPDFConfiguration()
        let zoom = webKit.webView.pageZoom
        configuration.rect = rect.map { CGRect(x: $0.minX * zoom, y: $0.minY * zoom, width: $0.width * zoom, height: $0.height * zoom) } ?? webKit.webView.bounds
        let pdf: Data = try await withCheckedThrowingContinuation { continuation in
            webKit.webView.createPDF(configuration: configuration) { continuation.resume(with: $0) }
        }
        return try shrink(try PageExport.encode(try PageExport.rasterize(pdf: pdf), jpeg: true))
    }

    private static func shrink(_ data: Data) throws -> Data {
        guard let image = NSBitmapImageRep(data: data) else { throw Failure("No screenshot.") }
        let width = image.pixelsWide, height = image.pixelsHigh
        guard width > 1280 else { return data }
        let scale = 1280.0 / Double(width)
        let target = NSSize(width: 1280, height: Double(height) * scale)
        guard let resized = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(target.width), pixelsHigh: Int(target.height),
                                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                             colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return data }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: resized)
        image.draw(in: NSRect(origin: .zero, size: target))
        NSGraphicsContext.restoreGraphicsState()
        return resized.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) ?? data
    }
}
