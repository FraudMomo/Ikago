import Darwin
import Foundation

/// Memory and CPU of Ikago as Activity Monitor groups it: the app, its Chromium helpers and its WebKit processes.
struct PerformanceSample: Sendable {
    /// Physical footprint in bytes, summed over every process.
    var memory: UInt64 = 0
    /// Percent of one core over the last interval, summed (so it can pass 100).
    var cpu: Double = 0
    var processes = 0
}

/// Reads the numbers off the main thread, once a second, only while an overlay is showing.
final class PerformanceSampler: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.ikago.performance", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var cpuTime: [pid_t: UInt64] = [:]
    private var lastUptime: UInt64 = 0

    func start(_ report: @escaping @MainActor (PerformanceSample) -> Void) {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 1, leeway: .milliseconds(50))
        timer.setEventHandler { [weak self] in
            guard let sample = self?.sample() else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { report(sample) } }
        }
        queue.async { self.timer = timer }
        timer.resume()
    }

    func stop() {
        queue.async {
            self.timer?.cancel()
            self.timer = nil
            self.cpuTime = [:]
            self.lastUptime = 0
        }
    }

    // SPI: WebKit's processes are started by launchd, not by Ikago, so only the "responsible process" links them to
    // the app. Without the symbol the overlay counts the app and its child processes only.
    private typealias Responsible = @convention(c) (pid_t) -> pid_t
    private static let responsible: Responsible? = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid")
        .map { unsafeBitCast($0, to: Responsible.self) }

    private static let timebase: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom)
    }()

    private func sample() -> PerformanceSample {
        let own = getpid()
        var pids = [pid_t](repeating: 0, count: Int(proc_listallpids(nil, 0)) + 32)
        let count = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.stride)))
        let now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        var result = PerformanceSample()
        var times: [pid_t: UInt64] = [:]
        var busy: UInt64 = 0
        for pid in pids.prefix(max(0, count)) where pid > 0 && (pid == own || Self.belongs(pid, to: own)) {
            var info = rusage_info_v4()
            let status = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
            }
            guard status == 0 else { continue }
            result.memory += info.ri_phys_footprint
            result.processes += 1
            let time = info.ri_user_time + info.ri_system_time
            times[pid] = time
            if let before = cpuTime[pid], time > before { busy += time - before }
        }
        if lastUptime > 0, now > lastUptime {
            result.cpu = Double(busy) * Self.timebase / Double(now - lastUptime) * 100
        }
        cpuTime = times
        lastUptime = now
        return result
    }

    /// What Activity Monitor groups under the app: launched from a terminal, that is the terminal, not Ikago.
    private static let group: pid_t = responsible.map { $0(getpid()) } ?? getpid()

    private static func belongs(_ pid: pid_t, to own: pid_t) -> Bool {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.stride)
        if proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size, info.pbi_ppid == UInt32(own) { return true }
        guard let responsible, responsible(pid) == group else { return false }
        if group == own { return true }
        // A development run from a terminal shares its group with the terminal's other processes: take WebKit's only.
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { return false }
        let bytes = path.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self).contains("/WebKit.framework/")
    }
}
