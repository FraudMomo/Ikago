import Foundation

/// The MCP tools Ikago offers agents (`AgentServer`), with their input schemas and what each returns. Every page answer
/// is the compact outline (`AgentPageScript`) or only what changed, never the page's HTML.
@MainActor
enum AgentTools {
    static let instructions = """
        Ikago is a web browser you can drive. Work in tabs of your own: open one with tab_open (it opens in the \
        background; the person keeps browsing). Read a page with outline: one line per landmark, heading, control and \
        short text, with refs like [e12]. Act with click, type, select, press and scroll, by ref. Each action returns \
        only what changed on the page (+ added, - removed, ~ changed, url, focus); call outline again only when you need \
        the whole picture. Refs stay valid until their element goes away. For long text use read (one part by ref, or \
        the main content); to locate something use find. Take a screenshot only when the outline can't tell you (canvas, \
        charts, images). Ikago never types passwords, card numbers or security codes and never shows them to you: when \
        a page needs one, ask the person to take over. Consequential actions (buying, paying, sending, posting, deleting, \
        booking, submitting a payment form) may wait for the person to allow them; if they decline, don't try another \
        way. The person can see, pause and stop you on every tab.
        """

    private static func tool(_ name: String, _ title: String, _ description: String, _ properties: [String: [String: Any]],
                             required: [String] = [], readOnly: Bool = false) -> [String: Any] {
        ["name": name, "title": title, "description": description,
         "inputSchema": ["type": "object", "properties": properties, "required": required, "additionalProperties": false],
         "annotations": ["readOnlyHint": readOnly, "openWorldHint": true]]
    }

    private static let tab: [String: Any] = ["type": "string", "description": "The tab, such as t1, from tab_open or tabs."]
    private static let ref: [String: Any] = ["type": "string", "description": "An element's ref from outline or find, such as e12."]

    static var list: [[String: Any]] {
        var tools = [
            tool("tabs", "List tabs", "The agent's tabs (and the person's, if they share them): id, title and address.", [:], readOnly: true),
            tool("tab_open", "Open a tab", "Opens a web page in a new background tab of the agent's and returns its id and outline.",
                 ["url": ["type": "string", "description": "The address, such as https://example.com."]], required: ["url"]),
            tool("navigate", "Go to an address", "Loads an address in the tab and returns its outline.",
                 ["tab": tab, "url": ["type": "string"]], required: ["tab", "url"]),
            tool("history", "Back, forward or reload", "Goes back or forward in the tab's history, or reloads it; returns the outline.",
                 ["tab": tab, "action": ["type": "string", "enum": ["back", "forward", "reload"]]], required: ["tab", "action"]),
            tool("tab_close", "Close a tab", "Closes one of the agent's tabs.", ["tab": tab], required: ["tab"]),
            tool("outline", "Outline the page", "The page as compact lines with refs: landmarks, headings, controls with their state, short text. Near the viewport by default; all for the whole page; ref for one part (a collapsed list).",
                 ["tab": tab, "ref": ref, "all": ["type": "boolean", "description": "The whole page, not just around the viewport."],
                  "text": ["type": "boolean", "description": "Include short text lines (default true)."]], required: ["tab"], readOnly: true),
            tool("read", "Read text", "The readable text of one part of the page (by ref) or of its main content.",
                 ["tab": tab, "ref": ref, "max": ["type": "integer", "description": "Most characters to return (default 4000)."]], required: ["tab"], readOnly: true),
            tool("find", "Find on the page", "Controls and headings whose name contains all the words.",
                 ["tab": tab, "query": ["type": "string"]], required: ["tab", "query"], readOnly: true),
            tool("click", "Click", "Clicks an element. Returns what changed.", ["tab": tab, "ref": ref], required: ["tab", "ref"]),
            tool("type", "Type", "Replaces a field's text (never a password field). submit presses Return after. Returns what changed.",
                 ["tab": tab, "ref": ref, "text": ["type": "string"], "submit": ["type": "boolean"]], required: ["tab", "ref", "text"]),
            tool("select", "Choose an option", "Chooses an option of a select by its value or text. Returns what changed.",
                 ["tab": tab, "ref": ref, "value": ["type": "string"]], required: ["tab", "ref", "value"]),
            tool("press", "Press a key", "Presses a key (Enter, Escape, Tab, ArrowDown…) in the focused element or the one by ref.",
                 ["tab": tab, "key": ["type": "string"], "ref": ref], required: ["tab", "key"]),
            tool("scroll", "Scroll", "Scrolls the page up or down by most of a screen, or an element into view.",
                 ["tab": tab, "direction": ["type": "string", "enum": ["up", "down", "left", "right"]], "ref": ref], required: ["tab"]),
            tool("wait", "Wait", "Waits for the page to settle (a few seconds at most), then returns what changed.",
                 ["tab": tab], required: ["tab"], readOnly: true),
            tool("screenshot", "Screenshot", "An image of what the tab shows, or of one element. Use when the outline can't tell.",
                 ["tab": tab, "ref": ref], required: ["tab"], readOnly: true),
        ]
        if AgentBrowser.usesOpenTabs {
            tools.append(tool("tab_use", "Use a tab of the person's", "Starts driving one of the person's open tabs (they see it).",
                              ["tab": tab], required: ["tab"]))
        }
        if BrowserSecurity.shared.preferences.agentAllowsScripts == true {
            tools.append(tool("evaluate", "Run a script", "Runs JavaScript in Ikago's isolated world of the page and returns its JSON result.",
                              ["tab": tab, "script": ["type": "string", "description": "A function body that returns a value."]], required: ["tab", "script"]))
        }
        return tools
    }

    /// Runs one tool. Returns MCP content blocks, and whether it failed.
    static func call(_ name: String, _ arguments: [String: Any]) async -> (content: [[String: Any]], isError: Bool) {
        func string(_ key: String) -> String? { arguments[key] as? String }
        func need(_ key: String) throws -> String {
            guard let value = string(key), !value.isEmpty else { throw AgentBrowser.Failure("Missing \(key).") }
            return key == "tab" ? AgentBrowser.resolve(value) : value
        }
        do {
            let text: String
            switch name {
            case "tabs": text = AgentBrowser.listTabs()
            case "tab_open":
                let id = try await AgentBrowser.open(try need("url"))
                text = "tab \(AgentBrowser.alias(id))\n" + (try await outline(id, [:]))
            case "tab_use":
                try AgentBrowser.use(try need("tab"))
                text = try await outline(try need("tab"), [:])
            case "tab_close":
                try AgentBrowser.close(try need("tab"))
                text = "Closed."
            case "navigate":
                let id = try need("tab"), url = try need("url")
                guard AddressResolver.isWebURL(url) else { throw AgentBrowser.Failure("Agents open web pages only (http or https).") }
                let page = try await AgentBrowser.page(id)
                AgentActivity.shared.begin(id, "Going to \(url)")
                page.load(url)
                await AgentBrowser.settle(id)
                AgentActivity.shared.end(id)
                text = try await outline(id, [:])
            case "history":
                let id = try need("tab"), page = try await AgentBrowser.page(id)
                switch try need("action") {
                case "back": page.goBack()
                case "forward": page.goForward()
                default: page.reload()
                }
                await AgentBrowser.settle(id)
                text = try await outline(id, [:])
            case "outline":
                var options: [String: Any] = [:]
                if let ref = string("ref") { options["ref"] = ref }
                if let all = arguments["all"] as? Bool { options["all"] = all }
                if let includeText = arguments["text"] as? Bool { options["text"] = includeText }
                text = try await outline(try need("tab"), options)
            case "read":
                let page = try await AgentBrowser.page(try need("tab"))
                var options: [String: Any] = ["max": min(arguments["max"] as? Int ?? 4000, 40000)]
                if let ref = string("ref") { options["ref"] = ref }
                text = try AgentBrowser.text(try await AgentBrowser.call(page, "text", options))
            case "find":
                let page = try await AgentBrowser.page(try need("tab"))
                text = try AgentBrowser.text(try await AgentBrowser.call(page, "find", ["query": try need("query")]))
            case "click": text = try await AgentBrowser.click(try need("tab"), ref: try need("ref"))
            case "type": text = try await AgentBrowser.type(try need("tab"), ref: try need("ref"), text: try need("text"),
                                                            submit: arguments["submit"] as? Bool ?? false)
            case "select": text = try await AgentBrowser.select(try need("tab"), ref: try need("ref"), value: try need("value"))
            case "press": text = try await AgentBrowser.press(try need("tab"), key: try need("key"), ref: string("ref"))
            case "scroll": text = try await AgentBrowser.scroll(try need("tab"), ref: string("ref"), direction: string("direction") ?? "down")
            case "wait":
                let id = try need("tab")
                await AgentBrowser.settle(id)
                text = try AgentBrowser.text(try await AgentBrowser.call(try await AgentBrowser.page(id), "changes"))
            case "screenshot":
                let data = try await AgentBrowser.screenshot(try need("tab"), ref: string("ref"))
                return ([["type": "image", "data": data.base64EncodedString(), "mimeType": "image/jpeg"]], false)
            case "evaluate":
                guard BrowserSecurity.shared.preferences.agentAllowsScripts == true else { throw AgentBrowser.Failure("Scripts aren't allowed.") }
                let id = try need("tab")
                try AgentBrowser.check(id)
                AgentActivity.shared.begin(id, "Running a script")
                defer { AgentActivity.shared.end(id) }
                let value = try await AgentBrowser.page(id).callAsync(try need("script"))
                let data = (try? JSONSerialization.data(withJSONObject: ["result": value ?? NSNull()], options: [.fragmentsAllowed])) ?? Data()
                text = String(decoding: data, as: UTF8.self)
            default: throw AgentBrowser.Failure("Unknown tool \(name).")
            }
            return ([["type": "text", "text": text]], false)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            AgentActivity.shared.record("\(name): \(message)", failed: true)
            return ([["type": "text", "text": message]], true)
        }
    }

    private static func outline(_ tabID: String, _ options: [String: Any]) async throws -> String {
        let page = try await AgentBrowser.page(tabID)
        return try AgentBrowser.text(try await AgentBrowser.call(page, "outline", options))
    }
}
