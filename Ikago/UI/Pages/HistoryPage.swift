import AppKit
import SwiftUI

/// ikago://history: searchable, grouped by day; click to open, right-click to remove.
struct HistoryPage: View {
    let state: BrowserState
    weak var commands: BrowserCommands?
    @State private var query = ""

    var body: some View {
        let colors = state.palette
        PageScaffold(title: "History", colors: colors, trailing: AnyView(
            TextField("Search history", text: $query)
                .textFieldStyle(.plain)
                .padding(.horizontal, 14).frame(width: 240, height: 34)
                .background(Capsule().fill(Color.primary.opacity(0.05))))) {
            let groups = grouped
            if groups.isEmpty {
                EmptyNote(symbol: "clock", text: query.isEmpty ? "No history yet" : "No matches")
            }
            ForEach(groups, id: \.title) { group in
                PageSection(title: group.title) {
                    ForEach(Array(group.visits.enumerated()), id: \.element.url) { index, visit in
                        if index > 0 { PageDivider() }
                        Button { commands?.openInNewTab(visit.url) } label: { HistoryRow(visit: visit) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Remove from History") {
                                    withAnimation(.ikago) { state.history.removeAll { $0.url == visit.url } }
                                    state.scheduleSave()
                                }
                            }
                    }
                }
            }
            if !state.history.isEmpty {
                Button("Clear History…", role: .destructive) { clear() }.controlSize(.small)
            }
        }
    }

    private var grouped: [(title: String, visits: [Visit])] {
        let needle = query.lowercased()
        let visits = needle.isEmpty ? state.history
            : state.history.filter { $0.url.lowercased().contains(needle) || $0.title.lowercased().contains(needle) }
        let calendar = Calendar.current
        var result: [(title: String, visits: [Visit])] = []
        for visit in visits.prefix(500) {
            let date = Date(timeIntervalSince1970: Double(visit.time) / 1000)
            let title = calendar.isDateInToday(date) ? "Today"
                : calendar.isDateInYesterday(date) ? "Yesterday"
                : date.formatted(date: .complete, time: .omitted)
            if result.last?.title == title { result[result.count - 1].visits.append(visit) } else { result.append((title, [visit])) }
        }
        return result
    }

    private func clear() {
        let alert = NSAlert()
        alert.messageText = "Clear all browsing history?"
        alert.addButton(withTitle: "Clear History")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        withAnimation(.ikago) { state.history.removeAll() }
        state.scheduleSave()
    }
}

private struct HistoryRow: View {
    let visit: Visit

    var body: some View {
        HStack(spacing: 10) {
            FaviconView(pageURL: visit.url)
            VStack(alignment: .leading, spacing: 1) {
                Text(visit.title.isEmpty ? AddressResolver.hostname(visit.url) : visit.title).lineLimit(1)
                Text(AddressResolver.hostname(visit.url)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(Date(timeIntervalSince1970: Double(visit.time) / 1000).formatted(date: .omitted, time: .shortened))
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

struct EmptyNote: View {
    let symbol: String
    let text: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 28, weight: .light))
            Text(text)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, minHeight: 240)
    }
}
