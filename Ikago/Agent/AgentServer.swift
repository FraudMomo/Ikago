import CryptoKit
import Foundation
import Network
import Observation

/// Ikago's MCP server for agents (Settings ▸ Agents): off by default, on this Mac only, and every request needs the
/// token. Streamable HTTP without streaming: `POST /mcp` with JSON-RPC, answered with JSON.
///
/// - Bound to 127.0.0.1 over the loopback interface: nothing on the network can reach it.
/// - A browser page can't use it either: requests with an `Origin` are refused (pages always send one), and the `Host`
///   must be the loopback address (no DNS rebinding).
/// - The token is 32 random bytes, compared in constant time, and kept sealed on this Mac (`AgentCredentials`).
@MainActor @Observable
final class AgentServer {
    static let shared = AgentServer()
    static let defaultPort: UInt16 = 47811
    static let supportedVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]

    private(set) var port: UInt16?
    private(set) var problem: String?
    @ObservationIgnored private var listener: NWListener?
    /// Which agent each MCP session belongs to, from its handshake, so its actions show under its name.
    @ObservationIgnored private var sessions: [String: AgentIdentity] = [:]

    var endpoint: String? { port.map { "http://127.0.0.1:\($0)/mcp" } }
    var isOn: Bool { BrowserSecurity.shared.preferences.agentAccess == true }

    /// Starts or stops the server to match the setting.
    func update() {
        if isOn { if listener == nil { start() } } else { stop() }
    }

    private func start() {
        let wanted = UInt16(clamping: BrowserSecurity.shared.preferences.agentPort ?? Int(Self.defaultPort))
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: wanted) ?? 47811)
        do {
            let listener = try NWListener(using: parameters)
            listener.newConnectionHandler = { connection in
                MainActor.assumeIsolated { AgentServer.shared.accept(connection) }
            }
            listener.stateUpdateHandler = { state in
                MainActor.assumeIsolated {
                    let server = AgentServer.shared
                    switch state {
                    case .ready: server.port = listener.port?.rawValue; server.problem = nil
                    case .failed(let error):
                        server.problem = "Ikago couldn’t listen on port \(wanted): \(error.localizedDescription)"
                        server.stop(keepProblem: true)
                    default: break
                    }
                }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            problem = "Ikago couldn’t start the agent server: \(error.localizedDescription)"
        }
    }

    func stop(keepProblem: Bool = false) {
        listener?.cancel()
        listener = nil
        port = nil
        if !keepProblem { problem = nil }
    }

    // MARK: HTTP

    private func accept(_ connection: NWConnection) {
        connection.start(queue: .main)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, complete, error in
            MainActor.assumeIsolated {
                var buffer = buffer
                if let data { buffer.append(data) }
                if let request = HTTPRequest(buffer) {
                    AgentServer.shared.handle(request, on: connection)
                } else if error != nil || complete || buffer.count > 2_000_000 {
                    connection.cancel()
                } else {
                    AgentServer.shared.receive(connection, buffer: buffer)
                }
            }
        }
    }

    private func send(_ connection: NWConnection, status: String, headers: [String: String] = [:], body: Data = Data()) {
        var head = "HTTP/1.1 \(status)\r\nContent-Length: \(body.count)\r\nConnection: close\r\nCache-Control: no-store\r\n"
        for (name, value) in headers { head += "\(name): \(value)\r\n" }
        connection.send(content: Data((head + "\r\n").utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
    }

    private func handle(_ request: HTTPRequest, on connection: NWConnection) {
        guard let port, ["127.0.0.1:\(port)", "localhost:\(port)"].contains(request.headers["host"] ?? "") else {
            return send(connection, status: "403 Forbidden")
        }
        // Pages always send an Origin; MCP clients don't. A page reaching this server is refused outright.
        if let origin = request.headers["origin"], origin != "null" { return send(connection, status: "403 Forbidden") }
        guard request.path == "/mcp" || request.path == "/" else { return send(connection, status: "404 Not Found") }
        guard request.method == "POST" else { return send(connection, status: "405 Method Not Allowed", headers: ["Allow": "POST"]) }
        guard AgentCredentials.matches(request.headers["authorization"]) else {
            AgentActivity.shared.record("Refused a request without the right token", failed: true)
            return send(connection, status: "401 Unauthorized", headers: ["WWW-Authenticate": "Bearer"])
        }
        guard let json = try? JSONSerialization.jsonObject(with: request.body) else {
            return reply(connection, [error(nil, -32700, "Parse error")], session: nil)
        }
        let messages = (json as? [[String: Any]]) ?? [(json as? [String: Any]) ?? [:]]
        Task { @MainActor in
            var replies: [[String: Any]] = []
            var session: String?
            let server = AgentServer.shared
            let named = request.headers["mcp-session-id"].flatMap { server.sessions[$0] }
            for message in messages {
                if message["method"] as? String == "initialize" { session = UUID().uuidString }
                let answer = await AgentActivity.$current.withValue(named) { await server.answer(message, session: session) }
                if let answer { replies.append(answer) }
            }
            if replies.isEmpty { return AgentServer.shared.send(connection, status: "202 Accepted") }
            AgentServer.shared.reply(connection, replies, single: !(json is [Any]), session: session)
        }
    }

    private func reply(_ connection: NWConnection, _ replies: [[String: Any]], single: Bool = true, session: String?) {
        let object: Any = single && replies.count == 1 ? replies[0] : replies
        let body = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
        var headers = ["Content-Type": "application/json"]
        if let session { headers["Mcp-Session-Id"] = session }
        send(connection, status: "200 OK", headers: headers, body: body)
    }

    // MARK: JSON-RPC

    private func error(_ id: Any?, _ code: Int, _ message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": code, "message": message]]
    }

    private func answer(_ message: [String: Any], session: String?) async -> [String: Any]? {
        guard let id = message["id"] else { return nil }  // a notification
        let params = message["params"] as? [String: Any] ?? [:]
        func result(_ value: [String: Any]) -> [String: Any] { ["jsonrpc": "2.0", "id": id, "result": value] }
        switch message["method"] as? String {
        case "initialize":
            let requested = params["protocolVersion"] as? String ?? ""
            let info = params["clientInfo"] as? [String: Any]
            let identity = AgentIdentity(client: info?["name"] as? String ?? "", title: info?["title"] as? String)
            if let session {
                if sessions.count > 64 { sessions.removeAll() }
                sessions[session] = identity
            }
            AgentActivity.shared.connected(identity)
            AgentActivity.$current.withValue(identity) { AgentActivity.shared.record("Connected") }
            return result(["protocolVersion": Self.supportedVersions.contains(requested) ? requested : Self.supportedVersions[0],
                           "capabilities": ["tools": ["listChanged": false]],
                           "serverInfo": ["name": "Ikago", "title": "Ikago", "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"],
                           "instructions": AgentTools.instructions])
        case "ping": return result([:])
        case "tools/list": return result(["tools": AgentTools.list])
        case "tools/call":
            guard let name = params["name"] as? String else { return error(id, -32602, "Missing tool name") }
            let outcome = await AgentTools.call(name, params["arguments"] as? [String: Any] ?? [:])
            return result(["content": outcome.content, "isError": outcome.isError])
        default:
            return error(id, -32601, "Method not found")
        }
    }
}

/// A complete HTTP/1.1 request from the bytes received so far, or nil while more are expected.
private struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data

    init?(_ data: Data) {
        guard let end = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(decoding: data[..<end.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
        let start = head.first?.split(separator: " ") ?? []
        guard start.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in head.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        guard length >= 0, data.count - end.upperBound >= length else { return nil }
        method = String(start[0])
        path = String(start[1].split(separator: "?").first ?? "")
        self.headers = headers
        body = data[end.upperBound..<(end.upperBound + length)]
    }
}

/// The agent token, sealed on this Mac (`SealedStorage`). Made the first time it is needed; Regenerate replaces it, so
/// every connected agent must be given the new one.
@MainActor
enum AgentCredentials {
    private static var file: URL { SessionStore.standard.directory.appending(path: "agent.sealed") }
    private static var cached: String?

    static var token: String {
        if let cached { return cached }
        if let data = try? Data(contentsOf: file), let plain = try? SealedStorage.open(data), let text = String(data: plain, encoding: .utf8),
           text.count >= 32 {
            cached = text
            return text
        }
        return regenerate()
    }

    @discardableResult
    static func regenerate() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let token = Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        if let sealed = try? SealedStorage.seal(Data(token.utf8)) {
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? sealed.write(to: file, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        }
        cached = token
        return token
    }

    /// Whether an `Authorization` header carries the token, compared in constant time.
    static func matches(_ header: String?) -> Bool {
        guard let header, header.hasPrefix("Bearer ") else { return false }
        let given = Data(header.dropFirst(7).utf8), expected = Data(token.utf8)
        let key = SymmetricKey(size: .bits256)
        return HMAC<SHA256>.authenticationCode(for: given, using: key) == HMAC<SHA256>.authenticationCode(for: expected, using: key)
    }
}
