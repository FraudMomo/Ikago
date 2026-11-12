import Foundation

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
