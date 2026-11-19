import SwiftUI

/// The bar at the foot of a tab an agent drives: who is driving, what it is doing, and Pause or Stop; when it wants to
/// do something consequential (buy, pay, send, post, delete), Don't Allow, Allow on the site, or Allow Once instead.
struct AgentBar: View {
    let tabID: String
    let colors: Palette
    private var activity: AgentActivity { .shared }

    var body: some View {
        let state = activity.tabs[tabID]
        let approval = activity.approval(for: tabID)
        HStack(spacing: 12) {
            let agent = state?.agent ?? .unknown
            AgentBadge(agent: agent, working: state?.working == true && state?.paused != true, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(approval == nil ? agent.name + (state?.paused == true ? " · Paused" : "") : "Allow \(agent.name) to do this?")
                    .font(.system(size: 12.5, weight: .semibold))
                Text(approval?.action ?? state?.status ?? "Waiting")
                    .font(.system(size: 11.5)).foregroundStyle(colors.secondary).lineLimit(1).truncationMode(.tail)
                    .contentTransition(.opacity)
            }
            .frame(minWidth: 160, maxWidth: 320, alignment: .leading)
            if let approval {
                Button("Don’t Allow") { activity.answer(approval.id, .deny) }.buttonStyle(SettingsButtonStyle())
                if !approval.site.isEmpty {
                    Button("Allow on \(approval.site)") { activity.answer(approval.id, .site) }.buttonStyle(SettingsButtonStyle())
                        .help("Agents act on \(approval.site) without asking until you stop them or quit Ikago")
                }
                Button("Allow Once") { activity.answer(approval.id, .once) }.buttonStyle(SettingsButtonStyle(prominent: true))
            } else {
                Button(state?.paused == true ? "Resume" : "Pause") { activity.setPaused(tabID, !(state?.paused ?? false)) }
                    .buttonStyle(SettingsButtonStyle())
                    .help(state?.paused == true ? "Let the agent continue here" : "Hold the agent here until you resume")
                Button("Stop") { activity.stop(tabID) }.buttonStyle(SettingsButtonStyle())
                    .help("Take this tab back: the agent can't act here again")
            }
        }
        .controlSize(.small)
        .padding(.leading, 14).padding(.trailing, 10).padding(.vertical, 9)
        .foregroundStyle(colors.text)
        .modalSurface(colors, radius: 22, tint: 0.15)
        .animation(.ikagoQuick, value: state)
        .animation(.ikagoQuick, value: approval)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(state?.agent.name ?? "An agent") is driving this tab")
    }
}

/// While agents drive tabs: a chip at the top right with each driving agent's mark and how many tabs, a menu to go to
/// each tab, and Stop for one agent or all of them.
struct AgentStatusChip: View {
    let state: BrowserState
    let colors: Palette
    private var activity: AgentActivity { .shared }

    var body: some View {
        let ids = activity.tabs.keys.filter { state.tab($0) != nil }
        let agents = Array(Set(ids.compactMap { activity.tabs[$0]?.agent })).sorted { $0.name < $1.name }
        let working = ids.contains { activity.tabs[$0]?.working == true }
        Menu {
            ForEach(agents, id: \.self) { agent in
                Section(agent.name) {
                    ForEach(activity.tabs(of: agent).filter { state.tab($0) != nil }, id: \.self) { id in
                        Button(state.tab(id)?.displayTitle ?? id) { state.select(id) }
                    }
                    if agents.count > 1 { Button("Stop \(agent.name)") { activity.stop(agent) } }
                }
            }
            if let first = activity.approvals.first {
                Divider()
                Button("Waiting for you: \(first.action)") { state.select(first.tabID) }
            }
            Divider()
            Button(agents.count > 1 ? "Stop All Agents" : "Stop \(agents.first?.name ?? "Agent")", role: .destructive) { activity.stopAll() }
        } label: {
            HStack(spacing: 7) {
                HStack(spacing: -3) {
                    ForEach(Array(agents.prefix(3).enumerated()), id: \.element) { index, agent in
                        AgentBadge(agent: agent, working: working && agents.count == 1, size: 20).zIndex(Double(-index))
                    }
                }
                Text(label(agents, tabs: ids.count)).font(.system(size: 12, weight: .semibold))
            }
            .padding(.leading, 6).padding(.trailing, 11).frame(height: 30)
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .foregroundStyle(activity.approvals.isEmpty ? colors.text : Color(hex: 0x7C3AED))
        .modalSurface(colors, radius: 15, tint: 0.15)
        .help("Tabs agents drive")
    }

    private func label(_ agents: [AgentIdentity], tabs: Int) -> String {
        let who = agents.count == 1 ? agents[0].name : "\(agents.count) agents"
        if !activity.approvals.isEmpty { return "\(who) needs you" }
        return "\(who) · \(tabs) \(tabs == 1 ? "tab" : "tabs")"
    }
}
