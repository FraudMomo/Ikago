import Foundation

/// Which agent is connected, from the name its MCP client gives in the handshake (`clientInfo`), so the UI can show
/// "Claude Code" with Claude's mark instead of "claude-code". The name is the client's own claim: it labels the agent
/// for the person and grants nothing (the token does).
struct AgentIdentity: Hashable, Sendable {
    enum Brand: String, Sendable, CaseIterable {
        case claude, openai, gemini, cursor, copilot, windsurf, zed, generic
    }

    let name: String
    let brand: Brand

    static let unknown = AgentIdentity(name: "Agent", brand: .generic)

    init(name: String, brand: Brand) {
        self.name = name
        self.brand = brand
    }

    /// `clientInfo.name` and `clientInfo.title` as the client sent them.
    init(client: String, title: String? = nil) {
        let key = (client + " " + (title ?? "")).lowercased()
        func has(_ words: String...) -> Bool { words.contains { key.contains($0) } }
        let known: (String, Brand)? =
            if has("claude-code", "claude code") { ("Claude Code", .claude) }
            else if has("claude") { ("Claude", .claude) }
            else if has("codex") { ("Codex", .openai) }
            else if has("chatgpt", "openai") { ("ChatGPT", .openai) }
            else if has("gemini") { ("Gemini CLI", .gemini) }
            else if has("cursor") { ("Cursor", .cursor) }
            else if has("copilot", "visual studio code", "vscode") { ("VS Code", .copilot) }
            else if has("windsurf", "codeium") { ("Windsurf", .windsurf) }
            else if has("zed") { ("Zed", .zed) }
            else { nil }
        if let known {
            self.init(name: known.0, brand: known.1)
        } else {
            let shown = (title?.isEmpty == false ? title! : client).trimmingCharacters(in: .whitespacesAndNewlines)
            self.init(name: shown.isEmpty ? "Agent" : String(shown.prefix(40)), brand: .generic)
        }
    }
}

/// How to connect each agent we know: one thing to copy, and where it goes. Every one carries the token, so copying is
/// the only way it leaves Ikago.
struct AgentSetup: Identifiable, Sendable {
    let id: String
    let identity: AgentIdentity
    /// Where the copied text goes ("Run in Terminal").
    let instruction: String
    let text: @Sendable (_ endpoint: String, _ token: String) -> String

    static let all: [AgentSetup] = [
        AgentSetup(id: "claude", identity: .init(name: "Claude Code", brand: .claude), instruction: "Run in Terminal") {
            "claude mcp add --transport http ikago \($0) --header \"Authorization: Bearer \($1)\""
        },
        AgentSetup(id: "codex", identity: .init(name: "Codex", brand: .openai), instruction: "Add to ~/.codex/config.toml") {
            "[mcp_servers.ikago]\nurl = \"\($0)\"\nhttp_headers = { \"Authorization\" = \"Bearer \($1)\" }\n"
        },
        AgentSetup(id: "cursor", identity: .init(name: "Cursor", brand: .cursor), instruction: "Add to ~/.cursor/mcp.json") {
            json(["mcpServers": ["ikago": ["url": $0, "headers": ["Authorization": "Bearer \($1)"]]]])
        },
        AgentSetup(id: "gemini", identity: .init(name: "Gemini CLI", brand: .gemini), instruction: "Add to ~/.gemini/settings.json") {
            json(["mcpServers": ["ikago": ["httpUrl": $0, "headers": ["Authorization": "Bearer \($1)"]]]])
        },
        AgentSetup(id: "vscode", identity: .init(name: "VS Code", brand: .copilot), instruction: "Run in Terminal") {
            "code --add-mcp '" + json(["name": "ikago", "type": "http", "url": $0, "headers": ["Authorization": "Bearer \($1)"]], pretty: false) + "'"
        },
    ]

    private static func json(_ object: [String: Any], pretty: Bool = true) -> String {
        let options: JSONSerialization.WritingOptions = pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: options) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}
