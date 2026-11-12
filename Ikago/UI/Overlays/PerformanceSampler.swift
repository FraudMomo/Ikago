import Darwin
import Foundation

/// Reads the numbers off the main thread, once a second, only while diagnostics are visible.
final class PerformanceSampler: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.ikago.performance", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var cpuTime: [pid_t: (started: UInt64, time: UInt64)] = [:]
    private var lastUptime: UInt64 = 0
    private var metadata: [pid_t: (started: UInt64, path: String, gpu: Bool)] = [:]

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
            self.metadata = [:]
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
        var times: [pid_t: (started: UInt64, time: UInt64)] = [:]
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
            times[pid] = (info.ri_proc_start_abstime, time)
            var cpu = 0.0
            if let before = cpuTime[pid], before.started == info.ri_proc_start_abstime, time >= before.time,
               lastUptime > 0, now > lastUptime {
                let delta = time - before.time
                busy += delta
                cpu = Double(delta) * Self.timebase / Double(now - lastUptime) * 100
            }
            let cached = metadata[pid].flatMap { $0.started == info.ri_proc_start_abstime ? $0 : nil }
            let path = cached?.path ?? Self.path(pid)
            let owner: PerformanceOwner = pid == own ? .app : path.contains("/WebKit.framework/") ? .webkit
                : path.contains("Ikago Helper") ? .chromium : .other
            let gpu = cached?.gpu ?? (path.localizedCaseInsensitiveContains("gpu") || (owner == .chromium && Self.isGPU(pid)))
            metadata[pid] = (info.ri_proc_start_abstime, path, gpu)
            result.rows.append(PerformanceProcess(id: pid, started: info.ri_proc_start_abstime, owner: owner,
                name: URL(fileURLWithPath: path).lastPathComponent, gpu: gpu, memory: info.ri_phys_footprint, cpu: cpu))
        }
        if lastUptime > 0, now > lastUptime {
            result.cpuAvailable = true
            result.cpu = Double(busy) * Self.timebase / Double(now - lastUptime) * 100
        }
        result.rows.sort { $0.memory > $1.memory }
        cpuTime = times
        metadata = metadata.filter { times[$0.key] != nil }
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
        return path(pid).contains("/WebKit.framework/")
    }

    private static func path(_ pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return "" }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private static func isGPU(_ pid: pid_t) -> Bool {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var buffer = [UInt8](repeating: 0, count: 65536)
        var size = buffer.count
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return false }
        // Read argv only; never inspect, retain or publish environment variables.
        let argc = buffer.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        guard argc > 0, argc < 4096 else { return false }
        var index = 4
        while index < size && buffer[index] != 0 { index += 1 }
        while index < size && buffer[index] == 0 { index += 1 }
        for _ in 0..<argc {
            let start = index
            while index < size && buffer[index] != 0 { index += 1 }
            if String(decoding: buffer[start..<index], as: UTF8.self) == "--type=gpu-process" { return true }
            index += 1
            if index >= size { break }
        }
        return false
    }
}
