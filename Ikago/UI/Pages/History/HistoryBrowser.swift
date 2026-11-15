import SwiftUI

// MARK: - History browser

/// The history list on ikago://history and in Settings ▸ History. Grouped by day (or by site), newest first; groups
/// are folded except the newest, and an open group shows its first rows with Show More, so a long history draws only a
/// handful of rows. Groups are built once per change of history, search or arrangement (never in `body`), and the
/// search waits for a pause in typing.
struct HistoryBrowser: View {
    let state: BrowserState
    weak var commands: BrowserCommands?
    @State private var query = ""
    @State private var applied = ""
    @State private var arrangement = HistoryArrangement.date
    @State private var groups: [HistoryGroup] = []
    @State private var expanded: Set<String> = []
    @State private var shown: [String: Int] = [:]
    private static let page = 25

    var body: some View {
        let colors = state.palette
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(colors.secondary)
                    TextField("Search history", text: $query).textFieldStyle(.plain).font(.system(size: 13))
                }
                .padding(.horizontal, 12).frame(height: 32)
                .background(Capsule().fill(Color.primary.opacity(0.05)))
                Picker("Arrange", selection: $arrangement) {
                    ForEach(HistoryArrangement.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden().pickerStyle(.segmented).fixedSize()
                Button { commands?.showClearData() } label: {
                    Text("Clear…").font(.system(size: 13, weight: .medium)).foregroundStyle(colors.text)
                        .padding(.horizontal, 14).frame(height: 32)
                        .background(Capsule().fill(Color.primary.opacity(0.05)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Clear Browsing Data")
            }
            if groups.isEmpty {
                EmptyNote(symbol: "clock", text: applied.isEmpty ? "No history yet" : "No matches")
            }
            ForEach(groups) { group in
                let open = !applied.isEmpty || expanded.contains(group.id)
                VStack(alignment: .leading, spacing: 6) {
                    HistoryGroupHeader(group: group, open: open, colors: colors) {
                        withAnimation(.ikagoQuick) { if expanded.remove(group.id) == nil { expanded.insert(group.id) } }
                    } remove: {
                        remove(Set(group.visits.map(\.url)))
                    }
                    if open { rows(group, colors: colors) }
                }
            }
        }
        .task(id: query) {
            // Searching waits for a short pause in typing, so each key doesn't regroup the whole history.
            if !query.isEmpty { try? await Task.sleep(for: .milliseconds(150)) }
            guard !Task.isCancelled else { return }
            applied = query
        }
        .onChange(of: state.history, initial: true) { rebuild() }
        .onChange(of: applied) { rebuild() }
        .onChange(of: arrangement) { expanded = []; rebuild() }
    }

    private func rows(_ group: HistoryGroup, colors: Palette) -> some View {
        let limit = shown[group.id] ?? Self.page
        return VStack(spacing: 0) {
            ForEach(Array(group.visits.prefix(limit).enumerated()), id: \.element.url) { index, visit in
                if index > 0 { PageDivider() }
                HistoryRow(visit: visit, showsSite: arrangement == .date, colors: colors) {
                    commands?.openInNewTab(visit.url)
                } remove: { remove([visit.url]) }
            }
            if group.visits.count > limit {
                PageDivider()
                Button("Show \(min(Self.page * 2, group.visits.count - limit)) More") {
                    shown[group.id] = limit + Self.page * 2
                }
                .buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(colors.accent)
                .frame(maxWidth: .infinity, minHeight: 34)
            }
        }
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.primary.opacity(0.045)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .transition(.opacity)
    }

    private func rebuild() {
        groups = HistoryGroup.build(state.history, query: applied, by: arrangement)
        // The newest group starts open.
        if expanded.isEmpty, let first = groups.first { expanded = [first.id] }
    }

    private func remove(_ urls: Set<String>) {
        let root = state.primary ?? state  // the first window's state saves, and shares it with the others
        root.history.removeAll { urls.contains($0.url) }
        root.scheduleSave()
    }
}

enum HistoryArrangement: String, CaseIterable, Identifiable {
    case date, site
    var id: String { rawValue }
    var title: String { self == .date ? "By Date" : "By Site" }
}

/// A day's (or a site's) visits, newest first.
struct HistoryGroup: Identifiable {
    let id: String
    let title: String
    let visits: [Visit]

    static func build(_ history: [Visit], query: String, by arrangement: HistoryArrangement) -> [HistoryGroup] {
        let needle = query.lowercased()
        let visits = (needle.isEmpty ? history : history.filter {
            $0.url.lowercased().contains(needle) || $0.title.lowercased().contains(needle)
        }).sorted { $0.time > $1.time }
        var order: [String] = []
        var buckets: [String: [Visit]] = [:]
        let calendar = Calendar.current
        for visit in visits {
            let key = arrangement == .date
                ? String(Int(calendar.startOfDay(for: visit.date).timeIntervalSince1970))
                : site(visit.url)
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(visit)
        }
        return order.map { key in
            let visits = buckets[key]!
            return HistoryGroup(id: key, title: arrangement == .date ? dayTitle(visits[0].date) : key, visits: visits)
        }
    }

    private static func site(_ url: String) -> String {
        let host = AddressResolver.hostname(url)
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private static func dayTitle(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let sameYear = calendar.isDate(date, equalTo: Date(), toGranularity: .year)
        return date.formatted(.dateTime.weekday(.wide).day().month(.wide).year(sameYear ? .omitted : .defaultDigits))
    }
}

/// A group's heading: click to fold or unfold; on hover, remove the whole group from history.
private struct HistoryGroupHeader: View {
    let group: HistoryGroup
    let open: Bool
    let colors: Palette
    let toggle: () -> Void
    let remove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Button(action: toggle) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(open ? 90 : 0)).frame(width: 12)
                    Text(group.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(colors.text)
                    Text("\(group.visits.count)").font(.system(size: 12).monospacedDigit()).foregroundStyle(colors.secondary)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).foregroundStyle(colors.secondary)
            Button("Remove", action: remove).buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(colors.secondary)
                .opacity(hovering ? 1 : 0).help("Remove these pages from history")
        }
        .padding(.horizontal, 4).frame(height: 26)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(open ? .isSelected : [])
    }
}

private struct HistoryRow: View {
    let visit: Visit
    let showsSite: Bool
    let colors: Palette
    let open: () -> Void
    let remove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Button(action: open) {
                HStack(spacing: 10) {
                    FaviconView(pageURL: visit.url)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(visit.title.isEmpty ? AddressResolver.hostname(visit.url) : visit.title)
                            .font(.system(size: 13)).foregroundStyle(colors.text).lineLimit(1)
                        Text(showsSite ? AddressResolver.hostname(visit.url) : visit.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: 11)).foregroundStyle(colors.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text(visit.date.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 11).monospacedDigit()).foregroundStyle(colors.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button(action: remove) {
                Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)).frame(width: 18, height: 18)
            }
            .buttonStyle(.plain).foregroundStyle(colors.secondary).opacity(hovering ? 1 : 0)
            .help("Remove from History")
        }
        .padding(.leading, 14).padding(.trailing, 10).frame(height: 46)
        .background(Color.primary.opacity(hovering ? 0.04 : 0))
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Open in New Tab", action: open)
            Button("Copy Address") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(visit.url, forType: .string)
            }
            Divider()
            Button("Remove from History", action: remove)
        }
    }
}

// MARK: - History page

/// ikago://history: the history list (`HistoryBrowser`), as Settings ▸ History shows it too.
struct HistoryPage: View {
    let state: BrowserState
    weak var commands: BrowserCommands?

    var body: some View {
        PageScaffold(title: "History", colors: state.palette) {
            HistoryBrowser(state: state, commands: commands)
        }
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
