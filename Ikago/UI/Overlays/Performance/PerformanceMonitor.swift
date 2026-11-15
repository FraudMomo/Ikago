import Foundation

// MARK: - Performance monitor

/// One shared sampler regardless of the number of open overlays or Performance tabs.
@MainActor @Observable
final class PerformanceMonitor {
    static let shared = PerformanceMonitor()
    private let sampler = PerformanceSampler()
    private var listeners: [UUID: @MainActor (PerformanceSample) -> Void] = [:]
    private(set) var sample = PerformanceSample()
    private(set) var history: [UInt64] = []
    private(set) var growth: UInt64 = 0
    private var baseline: UInt64?
    private var generation = 0
    var listenerCount: Int { listeners.count }

    func subscribe(_ listener: @escaping @MainActor (PerformanceSample) -> Void = { _ in }) -> UUID {
        let id = UUID()
        listeners[id] = listener
        if listeners.count == 1 {
            generation += 1
            let current = generation
            history = []; baseline = nil; growth = 0
            sampler.start { [weak self] sample in
                guard let self, self.generation == current, !self.listeners.isEmpty else { return }
                self.sample = sample
                self.history.append(sample.memory)
                if self.history.count > 120 { self.history.removeFirst() }
                if self.baseline == nil { self.baseline = sample.memory }
                self.growth = sample.memory > (self.baseline ?? 0) ? sample.memory - (self.baseline ?? 0) : 0
                PageLifetimeCanary.shared.check()
                for callback in Array(self.listeners.values) { callback(sample) }
            }
        }
        return id
    }

    func unsubscribe(_ id: UUID) {
        listeners[id] = nil
        if listeners.isEmpty { generation += 1; sampler.stop(); history = []; baseline = nil; growth = 0 }
    }
}

// MARK: - Performance sample

enum PerformanceOwner: String, CaseIterable, Sendable {
    case app = "App / shared", webkit = "WebKit", chromium = "Chromium", other = "Other"
}

struct PerformanceProcess: Identifiable, Sendable {
    let id: Int32
    let started: UInt64
    let owner: PerformanceOwner
    let name: String
    let gpu: Bool
    let memory: UInt64
    let cpu: Double
}

struct PerformanceSample: Sendable {
    var memory: UInt64 = 0
    var cpu: Double = 0
    var processes = 0
    var rows: [PerformanceProcess] = []
    var cpuAvailable = false

    func memory(for owner: PerformanceOwner) -> UInt64 {
        rows.filter { $0.owner == owner }.reduce(0) { $0 + $1.memory }
    }
    func cpu(for owner: PerformanceOwner) -> Double {
        rows.filter { $0.owner == owner }.reduce(0) { $0 + $1.cpu }
    }
    static func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .memory)
    }
}
