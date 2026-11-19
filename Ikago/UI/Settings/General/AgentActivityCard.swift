import AppKit
import SwiftUI

/// Settings ▸ Agents ▸ Activity: folded by default to one summary row. Opened, it reads like the History page: search,
/// a filter by agent, days with their counts, and Clear for the last hour, today or everything. The list scrolls inside
/// a fixed height, so a long log never lengthens the Settings page.
struct AgentActivityCard: View {
    private var activity: AgentActivity { .shared }
    @State private var open = Self.startsOpen
    /// Screenshots of the opened card (the debug driver's `agentstate:activityopen`).
    @MainActor static var startsOpen = false
    @State private var query = ""
    @State private var agent: AgentIdentity?

    var body: some View {
        PageSection(title: "Activity", footer: "Kept until you quit Ikago, up to the last 200 actions.") {
            header
            if open, !activity.log.isEmpty {
                PageDivider()
                filters.padding(.vertical, 10)
                list.transition(.opacity)
            }
        }
        .animation(.ikagoQuick, value: open)
    }

    // MARK: Summary row

    private var header: some View {
        PageRow(title: "Agent activity", subtitle: summary,
                figure: AnyView(Image(systemName: "list.bullet.rectangle").font(.system(size: 14)).foregroundStyle(.secondary).frame(width: 28))) {
            HStack(spacing: 8) {
                if !activity.log.isEmpty {
                    Menu("Clear") {
                        Button("Last Hour") { activity.clearLog(since: Date().addingTimeInterval(-3600)) }
                        Button("Today") { activity.clearLog(since: Calendar.current.startOfDay(for: Date())) }
                        Divider()
                        Button("Everything", role: .destructive) { activity.clearLog(since: nil) }
                    }
                    .menuStyle(.button).buttonStyle(SettingsButtonStyle()).fixedSize()
                    Button(open ? "Hide" : "Show") { open.toggle() }.buttonStyle(SettingsButtonStyle())
                }
            }
        }
    }

    private var summary: String {
        guard let last = activity.log.first else { return "What agents do shows here" }
        let count = activity.log.count
        return "\(count) \(count == 1 ? "action" : "actions") · last \(Self.when(last.date))"
    }

    // MARK: Search and filter

    private var filters: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(.secondary)
                TextField("Search activity", text: $query).textFieldStyle(.plain).font(.system(size: 13))
            }
            .padding(.horizontal, 12).frame(height: 30)
            .background(Capsule().fill(Color.primary.opacity(0.05)))
            let agents = activity.agents.map(\.identity)
            if agents.count > 1 {
                Picker("Agent", selection: $agent) {
                    Text("All Agents").tag(AgentIdentity?.none)
                    ForEach(agents, id: \.self) { Text($0.name).tag(AgentIdentity?.some($0)) }
                }
                .labelsHidden().fixedSize()
            }
        }
    }

    // MARK: The list

    private var list: some View {
        let days = Self.days(activity.log.filter { entry in
            (agent == nil || entry.agent == agent)
                && (query.isEmpty || entry.text.localizedCaseInsensitiveContains(query) || entry.agent.name.localizedCaseInsensitiveContains(query))
        })
        return Group {
            if days.isEmpty {
                Text("No matches").font(.system(size: 12)).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 60)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(days, id: \.title) { day in
                            Section {
                                ForEach(Array(day.entries.enumerated()), id: \.element.id) { index, entry in
                                    if index > 0 { Divider().opacity(0.5).padding(.leading, 34) }
                                    ActivityRow(entry: entry)
                                }
                            } header: {
                                HStack(spacing: 6) {
                                    Text(day.title).font(.system(size: 12, weight: .semibold))
                                    Text("\(day.entries.count)").font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
                                    Spacer()
                                }
                                .padding(.top, 8).padding(.bottom, 4).padding(.horizontal, 4)
                            }
                        }
                    }
                }
                .scrollIndicators(.automatic)
                .frame(height: min(360, CGFloat(days.reduce(0) { $0 + $1.entries.count }) * 44 + CGFloat(days.count) * 30 + 8))
                .padding(.bottom, 8)
            }
        }
    }

    private static func days(_ entries: [AgentActivity.Entry]) -> [(title: String, entries: [AgentActivity.Entry])] {
        let calendar = Calendar.current
        var result: [(title: String, entries: [AgentActivity.Entry])] = []
        for entry in entries {  // newest first already
            let title = dayTitle(entry.date, calendar)
            if result.last?.title == title { result[result.count - 1].entries.append(entry) } else { result.append((title, [entry])) }
        }
        return result
    }

    private static func dayTitle(_ date: Date, _ calendar: Calendar) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    static func when(_ date: Date) -> String {
        Calendar.current.isDateInToday(date) ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(date: .abbreviated, time: .shortened)
    }
}

/// One action: the agent's mark, what it did, which agent, and the time; a mark when it was refused or failed.
private struct ActivityRow: View {
    let entry: AgentActivity.Entry
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            AgentLogo(brand: entry.agent.brand, size: 14).frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.text).font(.system(size: 12.5)).lineLimit(1).truncationMode(.tail)
                Text(entry.agent.name).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if entry.failed {
                Image(systemName: "exclamationmark.circle").font(.system(size: 12)).foregroundStyle(.orange).help("Refused or failed")
            }
            Text(entry.date.formatted(date: .omitted, time: .standard))
                .font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4).frame(height: 44)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(hovering ? 0.04 : 0)))
        .onHover { hovering = $0 }
        .help(entry.text)
        .contextMenu {
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("\(entry.date.formatted()) · \(entry.agent.name) · \(entry.text)", forType: .string)
            }
        }
    }
}
