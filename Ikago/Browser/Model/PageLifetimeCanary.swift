import Foundation

/// Weak lifetime checks, not a heap profiler. No page content, URLs, disk writes or strong page references.
@MainActor @Observable
final class PageLifetimeCanary {
    static let shared = PageLifetimeCanary()
    private struct Retired {
        weak var object: AnyObject?
        let label: String
        let time: Date
    }
    private var records: [ObjectIdentifier: Retired] = [:]
    private var task: Task<Void, Never>?
    private(set) var warnings: [String] = []
    private(set) var dropped = 0
    isolated deinit { task?.cancel() }

    func retire(_ page: WebTab) {
        watch(page, label: "\(page.engine.rawValue.capitalized) page owner")
        watch(page.contentView, label: "\(page.engine.rawValue.capitalized) web view")
    }

    func watch(_ object: AnyObject, label: String, now: Date = Date()) {
        let id = ObjectIdentifier(object)
        guard records[id] == nil else { return }
        check(now: now)
        guard records.count < 200 else { dropped += 1; return }
        records[id] = Retired(object: object, label: label, time: now)
        guard task == nil else { return }
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled, let self else { return }
                self.check()
                if self.records.isEmpty { self.task = nil; return }
            }
        }
    }

    func check(now: Date = Date()) {
        records = records.filter { $0.value.object != nil }
        warnings = records.values.filter { now.timeIntervalSince($0.time) >= 30 }
            .map { "\($0.label) still retained after \(Int(now.timeIntervalSince($0.time))) s" }.sorted()
    }
}
