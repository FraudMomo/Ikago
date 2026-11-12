import SwiftUI
import Charts

struct PerformancePage: View {
    let state: BrowserState
    weak var commands: BrowserCommands?
    var tabID: String?
    @State private var monitor = PerformanceMonitor.shared
    @State private var canary = PageLifetimeCanary.shared
    @State private var subscription: UUID?
    private var colors: Palette { state.palette }

    private var tabs: [TabPerformanceEntry] { commands?.performanceTabs() ?? [] }

    private var isVisible: Bool { tabID.map { state.visibleTabIDs.contains($0) } ?? false }

    var body: some View {
        Group { if isVisible { dashboard } }
            .onAppear { syncSubscription() }
            .onChange(of: isVisible) { syncSubscription() }
            .onDisappear { if let subscription { monitor.unsubscribe(subscription) }; subscription = nil }
    }

    private var dashboard: some View {
        let entries = tabs
        let counts = Dictionary(grouping: entries.compactMap(\.pid), by: { $0 }).mapValues(\.count)
        let processesByPID = Dictionary(uniqueKeysWithValues: monitor.sample.rows.map { ($0.id, $0) })
        return PageScaffold(title: "Performance", colors: colors) {
            PageSection(title: "Browser", footer: "Physical memory footprint across readable processes. App / shared includes Chromium browser work. CPU is relative to one core and can exceed 100%.") {
                metric("Total", cpu: monitor.sample.cpu, memory: monitor.sample.memory,
                       detail: "\(monitor.sample.processes) processes")
                ForEach(PerformanceOwner.allCases, id: \.self) { owner in
                    if monitor.sample.rows.contains(where: { $0.owner == owner }) {
                        PageDivider()
                        metric(owner.rawValue, cpu: monitor.sample.cpu(for: owner), memory: monitor.sample.memory(for: owner))
                    }
                }
            }
            PageSection(title: "Memory over the last two minutes") {
                Chart(Array(monitor.history.enumerated()), id: \.offset) { entry in
                    LineMark(x: .value("Sample", entry.offset), y: .value("MiB", Double(entry.element) / 1_048_576))
                }
                .chartXAxis(.hidden).frame(height: 120).padding(16)
            }
            PageSection(title: "Leak canary", footer: "A retained closed page is a clue, not proof of a leak. Engine caches and shared services may keep process memory high after a page is released. Monitoring stays local.") {
                PageRow(title: canary.warnings.isEmpty ? "No overdue page releases detected" : "\(canary.warnings.count) overdue page releases",
                        subtitle: "Closed page owners and views are checked after 30 seconds") { EmptyView() }
                PageRow(title: "Growth since opening diagnostics", subtitle: "Includes new pages, caches and diagnostics") {
                    Text("+\(PerformanceSample.bytes(monitor.growth))").monospacedDigit()
                }
                ForEach(Array(canary.warnings.enumerated()), id: \.offset) { item in
                    PageRow(title: item.element) { EmptyView() }
                }
                if canary.dropped > 0 {
                    PageRow(title: "Tracking limit reached", subtitle: "\(canary.dropped) objects were not tracked") { EmptyView() }
                }
            }
            PageSection(title: "Tabs in this window", footer: "CPU and RAM below belong to the main renderer process. Shared processes repeat across rows; do not add them together. Subframes and engine services are included in browser totals. An unloaded tab has no live page; its small tab record remains on disk.") {
                LazyVStack(spacing: 0) {
                    ForEach(entries) { tab in
                        let process = tab.pid.flatMap { processesByPID[$0] }
                        let shared = tab.pid.map { (counts[$0] ?? 0) > 1 } ?? false
                        PageRow(title: tab.title, subtitle: "\(tab.engine) · \(tab.status)\(tab.parked > 0 ? " · \(tab.parked) parked pages" : "")") {
                            VStack(alignment: .trailing, spacing: 3) {
                                if let process {
                                    Text("\(Int(process.cpu.rounded()))% CPU · \(PerformanceSample.bytes(process.memory))").monospacedDigit()
                                    Text("PID \(process.id)\(shared ? " · shared" : "")").font(.caption).foregroundStyle(.secondary)
                                } else {
                                    Text(tab.status == "Unloaded" ? "Page released" : "No renderer measurement").foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            PageSection(title: "GPU services", footer: "These are GPU service CPU and RAM, not GPU utilization or video memory. Per-tab GPU counters are unavailable.") {
                let processes = monitor.sample.rows.filter(\.gpu)
                if processes.isEmpty {
                    PageRow(title: "No readable GPU service") { Text("GPU utilization: unavailable").foregroundStyle(.secondary) }
                }
                ForEach(processes) { process in
                    metric(process.owner.rawValue, cpu: process.cpu, memory: process.memory, detail: "PID \(process.id)")
                }
            }
            PageSection(title: "Processes", footer: "A missing renderer measurement can mean a page is starting, has no public mapping, or its process counters are inaccessible.") {
                ForEach(monitor.sample.rows) { process in
                    metric(process.name, cpu: process.cpu, memory: process.memory, detail: "\(process.owner.rawValue) · PID \(process.id)")
                }
            }
        }
    }

    private func syncSubscription() {
        if isVisible {
            if subscription == nil { subscription = monitor.subscribe() }
        } else if let subscription {
            monitor.unsubscribe(subscription)
            self.subscription = nil
        }
    }

    private func metric(_ title: String, cpu: Double, memory: UInt64, detail: String? = nil) -> some View {
        PageRow(title: title, subtitle: detail) {
            Text("\(monitor.sample.cpuAvailable ? "\(Int(cpu.rounded()))% CPU" : "Measuring CPU…") · \(PerformanceSample.bytes(memory))")
                .monospacedDigit()
        }
    }
}
