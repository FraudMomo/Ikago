import Foundation
import Observation

/// What agents are doing, for the person to see and steer: the tabs an agent drives, what it is doing in each, Pause and
/// Stop, approvals for actions that spend money, send or delete, and a log. The UI reads it (`AgentBar`, the agent badge on
/// tab icons, `AgentStatusChip`, Settings ▸ Agents); the MCP tools (`AgentTools`) wait on it before every action.
@MainActor @Observable
final class AgentActivity {
    static let shared = AgentActivity()

    struct TabState: Equatable {
        /// What the agent is doing now ("Clicking “Add to cart”"), or nil while it waits.
        var status: String?
        var paused = false
        var working = false
        /// Who drives it, for its badge and bar.
        var agent = AgentIdentity.unknown
    }

    struct Approval: Equatable, Identifiable {
        let id = UUID()
        let tabID: String
        let action: String
        /// The site it would happen on ("example.com"), for Allow on This Site.
        let site: String
    }

    enum Answer { case deny, once, site }

    struct Entry: Identifiable, Equatable {
        let id = UUID()
        let date = Date()
        let agent: AgentIdentity
        let text: String
        var failed = false
    }

    private(set) var tabs: [String: TabState] = [:]
    private(set) var approvals: [Approval] = []
    private(set) var log: [Entry] = []
    /// The agents that connected since Ikago started, most recent first, with when each last did something.
    private(set) var agents: [(identity: AgentIdentity, seen: Date)] = []
    /// The most recent agent, for a request that names no session.
    var client: AgentIdentity? { agents.first?.identity }
    /// The agent making the current request (`AgentServer` sets it from the MCP session).
    @TaskLocal static var current: AgentIdentity?
    private var acting: AgentIdentity { Self.current ?? client ?? .unknown }
    /// Sites where the person let agents act without asking, until they stop all agents or quit Ikago.
    private(set) var allowedSites: Set<String> = []
    @ObservationIgnored private var waiting: [UUID: CheckedContinuation<Bool, Never>] = [:]
    @ObservationIgnored private var resumers: [String: [CheckedContinuation<Void, Never>]] = [:]

    func drives(_ tabID: String) -> Bool { tabs[tabID] != nil }
    var isActive: Bool { !tabs.isEmpty }

    func adopt(_ tabID: String) { if tabs[tabID] == nil { tabs[tabID] = TabState(agent: acting) } }

    func connected(_ identity: AgentIdentity) {
        agents.removeAll { $0.identity == identity }
        agents.insert((identity, Date()), at: 0)
    }

    /// The tabs one agent drives.
    func tabs(of identity: AgentIdentity) -> [String] { tabs.filter { $0.value.agent == identity }.map(\.key).sorted() }

    /// Stops one agent everywhere it drives.
    func stop(_ identity: AgentIdentity) { for id in tabs(of: identity) { stop(id) } }

    /// An action starting on a tab: shown in its bar, and in the log.
    func begin(_ tabID: String?, _ status: String) {
        if let tabID, tabs[tabID] != nil { tabs[tabID]?.status = status; tabs[tabID]?.working = true }
        record(status)
    }

    func end(_ tabID: String?) {
        guard let tabID, tabs[tabID] != nil else { return }
        tabs[tabID]?.working = false
    }

    func record(_ text: String, failed: Bool = false) {
        let agent = acting
        if let index = agents.firstIndex(where: { $0.identity == agent }) { agents[index].seen = Date() }
        log.insert(Entry(agent: agent, text: text, failed: failed), at: 0)
        if log.count > 200 { log.removeLast(log.count - 200) }
    }

    /// Clears the log from a moment on, or all of it.
    func clearLog(since: Date?) {
        if let since { log.removeAll { $0.date >= since } } else { log.removeAll() }
    }

    // MARK: Pause and stop

    func setPaused(_ tabID: String, _ paused: Bool) {
        guard tabs[tabID] != nil else { return }
        tabs[tabID]?.paused = paused
        if !paused { resumers.removeValue(forKey: tabID)?.forEach { $0.resume() } }
    }

    /// Waits while the person has the tab paused. Returns false once they stopped the agent there.
    func waitIfPaused(_ tabID: String) async -> Bool {
        while let state = tabs[tabID], state.paused {
            await withCheckedContinuation { resumers[tabID, default: []].append($0) }
        }
        return tabs[tabID] != nil
    }

    /// The person takes the tab back: the agent can't act there again unless it opens it anew.
    func stop(_ tabID: String) {
        tabs[tabID] = nil
        resumers.removeValue(forKey: tabID)?.forEach { $0.resume() }
        for approval in approvals where approval.tabID == tabID { answer(approval.id, allow: false) }
        record("Stopped by you")
    }

    func stopAll() {
        for id in Array(tabs.keys) { stop(id) }
        allowedSites = []
    }

    func closed(_ tabID: String) {
        guard tabs[tabID] != nil else { return }
        tabs[tabID] = nil
        resumers.removeValue(forKey: tabID)?.forEach { $0.resume() }
    }

    // MARK: Approvals

    /// The site an approval covers: the registrable domain, so "Allow on shop.example.com" covers its checkout pages.
    static func site(of host: String) -> String {
        let host = host.lowercased().hasPrefix("www.") ? String(host.lowercased().dropFirst(4)) : host.lowercased()
        let domain = PublicSuffix.registrableDomain(host)
        return domain.isEmpty ? host : domain
    }

    /// Whether a consequential action may go ahead: at once when the person lets agents act without asking or allowed
    /// it on this site; otherwise they're asked in the tab's bar. Denied if they don't answer within two minutes.
    func approve(_ tabID: String, action: String, host: String) async -> Bool {
        let site = Self.site(of: host)
        if BrowserSecurity.shared.preferences.agentActsWithoutAsking == true {
            record("Did without asking: \(action)")
            return true
        }
        if !site.isEmpty, allowedSites.contains(site) {
            record("Allowed on \(site): \(action)")
            return true
        }
        let approval = Approval(tabID: tabID, action: action, site: site)
        approvals.append(approval)
        record("Asked you to allow: \(action)")
        let timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(120))
            self?.answer(approval.id, .deny)
        }
        defer { timeout.cancel() }
        return await withCheckedContinuation { waiting[approval.id] = $0 }
    }

    func answer(_ id: UUID, allow: Bool) { answer(id, allow ? .once : .deny) }

    func answer(_ id: UUID, _ answer: Answer) {
        guard let approval = approvals.first(where: { $0.id == id }) else { return }
        approvals.removeAll { $0.id == id }
        if answer == .site, !approval.site.isEmpty { allowedSites.insert(approval.site) }
        guard let waiter = waiting.removeValue(forKey: id) else { return }
        waiter.resume(returning: answer != .deny)
        switch answer {
        case .deny: record("Not allowed", failed: true)
        case .once: record("You allowed it")
        case .site: record("You allowed agents on \(approval.site) until you stop them")
        }
        // Other actions waiting on the same site go ahead too.
        if answer == .site {
            for other in approvals where other.site == approval.site { self.answer(other.id, .once) }
        }
    }

    /// Takes a site off the list of those where agents act without asking.
    func forget(site: String) { allowedSites.remove(site) }

    func approval(for tabID: String) -> Approval? { approvals.first { $0.tabID == tabID } }
}
