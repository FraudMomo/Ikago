import AppKit
import SwiftUI

/// Settings ▸ Agents: let agents on this Mac drive Ikago through its MCP server, connect one in a single copy, see and
/// stop the ones connected, choose what they may do, and what they did.
struct AgentSettingsSection: View {
    @Bindable var state: BrowserState
    private var server: AgentServer { .shared }
    private var activity: AgentActivity { .shared }
    @State private var copied: String?
    @State private var confirmingReset = false

    private var isOn: Bool { state.browserPreferences.agentAccess == true }

    var body: some View {
        PageSection(title: "Agent Access", footer: "Agents work in tabs of their own, and you can watch, pause or stop them on each tab. They never type passwords or card numbers, and never see them. Only apps on this Mac with Ikago’s token can connect.") {
            PageRow(title: "Allow agents", subtitle: "Claude Code, Codex and other AI agents on this Mac can browse with Ikago") {
                Toggle("Allow agents", isOn: Binding(get: { isOn }, set: { state.browserPreferences.agentAccess = $0 ? true : nil }))
                    .labelsHidden().toggleStyle(.switch)
            }
            if isOn {
                PageDivider()
                PageRow(title: statusTitle, subtitle: server.problem ?? server.endpoint.map { "Listening on \($0)" } ?? "",
                        figure: AnyView(Circle().fill(statusColor).frame(width: 8, height: 8).padding(.horizontal, 6))) { EmptyView() }
            }
        }
        if isOn, let endpoint = server.endpoint {
            connect(endpoint)
            connectedAgents
            permissions
            AgentActivityCard()
        }
    }

    private var statusTitle: String { server.problem != nil ? "Not running" : server.endpoint == nil ? "Starting…" : "Ready" }
    private var statusColor: Color { server.problem != nil ? .red : server.endpoint == nil ? .orange : .green }

    // MARK: Connect

    private func connect(_ endpoint: String) -> some View {
        PageSection(title: "Connect an Agent", footer: "Copy, then paste where it says. What you copy includes Ikago’s token, so paste it only into the agent’s own settings. Other MCP clients: add a Streamable HTTP server at the address, with the header Authorization: Bearer and the token.") {
            ForEach(AgentSetup.all) { setup in
                let seen = activity.agents.contains { $0.identity == setup.identity }
                PageRow(title: setup.identity.name, subtitle: seen ? "Connected" : setup.instruction, figure: AnyView(tile(setup.identity.brand))) {
                    copyButton(setup.text(endpoint, AgentCredentials.token), id: setup.id)
                }
                PageDivider()
            }
            PageRow(title: "Other MCP client", subtitle: endpoint, figure: AnyView(tile(.generic))) {
                HStack(spacing: 8) {
                    copyButton(endpoint, id: "address", label: "Copy Address")
                    copyButton(AgentCredentials.token, id: "token", label: "Copy Token")
                }
            }
            PageDivider()
            PageRow(title: "Reset token", subtitle: "Disconnects every agent until you connect it again") {
                Button("Reset…") { confirmingReset = true }.buttonStyle(SettingsButtonStyle())
                    .confirmationDialog("Reset the agent token?", isPresented: $confirmingReset) {
                        Button("Reset Token", role: .destructive) { activity.stopAll(); AgentCredentials.regenerate() }
                    } message: {
                        Text("Every connected agent stops working until you copy its setup again.")
                    }
            }
        }
    }

    // MARK: Connected

    @ViewBuilder private var connectedAgents: some View {
        if !activity.agents.isEmpty {
            PageSection(title: "Connected Agents", footer: "Agents that connected since Ikago started. An agent names itself, so a name here is what it says it is.") {
                ForEach(Array(activity.agents.enumerated()), id: \.element.identity) { index, entry in
                    if index > 0 { PageDivider() }
                    let driving = activity.tabs(of: entry.identity).count
                    PageRow(title: entry.identity.name,
                            subtitle: driving > 0 ? "Driving \(driving) \(driving == 1 ? "tab" : "tabs")"
                                : "Last active \(entry.seen.formatted(date: .omitted, time: .shortened))",
                            figure: AnyView(tile(entry.identity.brand))) {
                        if driving > 0 { Button("Stop") { activity.stop(entry.identity) }.buttonStyle(SettingsButtonStyle()) }
                    }
                }
            }
        }
    }

    // MARK: Permissions

    private var permissions: some View {
        PageSection(title: "What Agents May Do",
                    footer: "Consequential actions are buying, paying, sending, posting, deleting and booking, and anything that submits a payment form. Allow on a site lets agents act there without asking again until you stop them or quit Ikago.") {
            toggle("Ask before consequential actions", "Off: agents act without asking, as in an agent’s auto mode",
                   get: { $0.agentActsWithoutAsking != true }, set: { $0.agentActsWithoutAsking = $1 ? nil : true })
            if !activity.allowedSites.isEmpty {
                PageDivider()
                PageRow(title: "Allowed without asking", subtitle: activity.allowedSites.sorted().joined(separator: ", ")) {
                    Button("Ask Again") { for site in activity.allowedSites { activity.forget(site: site) } }.buttonStyle(SettingsButtonStyle())
                }
            }
            PageDivider()
            toggle("Use your open tabs", "Off: agents see and use only the tabs they open",
                   get: { $0.agentUsesOpenTabs == true }, set: { $0.agentUsesOpenTabs = $1 ? true : nil })
            PageDivider()
            toggle("Run scripts in pages", "Agents can run their own JavaScript in a page they drive",
                   get: { $0.agentAllowsScripts == true }, set: { $0.agentAllowsScripts = $1 ? true : nil })
        }
    }

    private func toggle(_ title: String, _ subtitle: String, get: @escaping (BrowserPreferences) -> Bool,
                        set: @escaping (inout BrowserPreferences, Bool) -> Void) -> some View {
        PageRow(title: title, subtitle: subtitle) {
            Toggle(title, isOn: Binding(get: { get(state.browserPreferences) }, set: { set(&state.browserPreferences, $0) }))
                .labelsHidden().toggleStyle(.switch)
        }
    }

    // MARK: Pieces

    /// An agent's mark on a small rounded tile, the same size on every row.
    private func tile(_ brand: AgentIdentity.Brand) -> some View {
        AgentLogo(brand: brand, size: 16)
            .frame(width: 28, height: 28)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
    }

    private func copyButton(_ text: String, id: String, label: String = "Copy") -> some View {
        Button(copied == id ? "Copied" : label) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = id
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { if copied == id { copied = nil } }
        }
        .buttonStyle(SettingsButtonStyle())
    }
}
