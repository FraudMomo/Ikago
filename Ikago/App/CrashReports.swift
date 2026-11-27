import AppKit
import Darwin
import SwiftUI

/// Crash reports a person can pass on by hand. Nothing is ever sent anywhere, and nothing is saved unasked.
///
/// Ikago leaves a small marker while it runs and removes it on a normal quit. When a launch finds the marker
/// still there, the last run ended unexpectedly, and a card at the top right of the window asks whether to report it
/// (`CrashReportCard`). Only on yes does Ikago gather what macOS wrote about it (its `.ips` crash reports, a
/// memory-pressure JetsamEvent) and a summary, remove the home folder, user and Mac names, save one zip to Downloads
/// and show it in Finder, for the person to send to the developer themselves. Help ▸ Save Crash Report saves one on
/// request.
/// The marker matters on its own: macOS sometimes loses the report itself (it can end `ReportCrashService` when the
/// Mac is short on memory), and then the summary is all there is.
@MainActor @Observable
final class CrashReports: NSObject {
    static let shared = CrashReports()

    /// What the marker records. It is rewritten when Ikago goes to the background, so it describes the last moments.
    private struct Marker: Codable {
        var pid: Int32
        var version: String
        var engine: String
        var started: Date
        var updated: Date
        var tabs: Int
        var windows: Int
        var memoryMB: Int
        var lastEvent: String
    }

    @ObservationIgnored private var marker: Marker?
    @ObservationIgnored private var tabCount: () -> Int = { 0 }
    /// The run that ended unexpectedly, while the card asks about it.
    @ObservationIgnored private var unexpected: Marker?
    @ObservationIgnored private var launched = Date()
    /// The card at the top right is asking whether to report the last run.
    private(set) var asking = false
    /// Saving the report (macOS may still be writing its own).
    private(set) var saving = false

    private var folder: URL { WebProfiles.isTestMode ? SessionStore.testDirectory : AppIdentity.dataDirectory }
    private var markerURL: URL { folder.appending(path: "Running.json") }
    private var handledURL: URL { folder.appending(path: "Crash reports handled.txt") }
    /// Debug test runs leave reports alone unless a test asks for them (`IKAGO_CRASH_REPORTS=1`).
    private var enabled: Bool { !WebProfiles.isTestMode || ProcessInfo.processInfo.environment["IKAGO_CRASH_REPORTS"] != nil }

    /// At launch: report an earlier run that ended unexpectedly, then mark this one as running.
    func start(tabs: @escaping () -> Int) {
        guard enabled else { return }
        tabCount = tabs
        if let data = try? Data(contentsOf: markerURL), let previous = try? JSONDecoder.iso8601.decode(Marker.self, from: data),
           previous.pid != getpid() {
            unexpected = previous
            // Once the window is up.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.5))
                withAnimation(.ikago) { self.asking = true }
            }
        }
        launched = Date()
        let now = Date()
        marker = Marker(pid: getpid(), version: Self.version, engine: BrowserRuntime.engine == .chromium ? "Chromium" : "WebKit",
                        started: now, updated: now, tabs: 0, windows: 0, memoryMB: 0, lastEvent: "launched")
        note("launched")
        // Every normal way out runs exit handlers; a crash, a memory kill or a force quit does not.
        Self.markerPath = markerURL
        atexit { if let path = CrashReports.markerPath { try? FileManager.default.removeItem(at: path) } }
        for (name, event) in [(NSApplication.didResignActiveNotification, "switched to another app"),
                              (NSApplication.didBecomeActiveNotification, "became active again")] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { CrashReports.shared.note(event) }
            }
        }
    }
    nonisolated(unsafe) private static var markerPath: URL?

    /// Updates the marker with what Ikago is doing now, such as "imported 340 tabs".
    func note(_ event: String) {
        guard var marker else { return }
        marker.updated = Date(); marker.lastEvent = event
        marker.tabs = tabCount()
        marker.windows = NSApp.windows.filter { $0.windowController is BrowserWindowController }.count
        marker.memoryMB = Self.footprintMB()
        self.marker = marker
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? JSONEncoder.pretty.encode(marker).write(to: markerURL, options: .atomic)
    }

    /// Yes on the card: the report is saved to Downloads and shown in Finder, for the person to send on.
    func report() {
        guard let previous = unexpected, !saving else { return }
        saving = true
        Task { @MainActor in
            // ReportCrash writes its report a few seconds after the process ends; a relaunch can come sooner.
            let wait = 8 - Date().timeIntervalSince(launched)
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            saveReport(since: previous.started, previous: previous, reveal: true)
            saving = false
            unexpected = nil
            withAnimation(.ikago) { asking = false }
        }
    }

    /// No on the card: this crash isn't asked about again.
    func dismiss() {
        if let previous = unexpected { markHandled(Self.reportFiles(since: previous.started.addingTimeInterval(-60))) }
        unexpected = nil
        withAnimation(.ikago) { asking = false }
    }

    private func markHandled(_ files: [URL]) {
        let handled = Set((try? String(contentsOf: handledURL, encoding: .utf8))?.split(separator: "\n").map(String.init) ?? [])
        let all = handled.union(files.map(\.lastPathComponent)).sorted().suffix(200)
        try? all.joined(separator: "\n").write(to: handledURL, atomically: true, encoding: .utf8)
    }

    /// Help ▸ Save Crash Report: the last week's reports, saved and shown in Finder.
    @objc func saveCrashReport(_ sender: Any?) {
        saveReport(since: Date().addingTimeInterval(-7 * 86_400), previous: nil, reveal: true)
    }

    @discardableResult
    private func saveReport(since start: Date, previous: Marker?, reveal: Bool) -> Bool {
        let handled = previous == nil ? Set<String>() : Set((try? String(contentsOf: handledURL, encoding: .utf8))?.split(separator: "\n").map(String.init) ?? [])
        let files = Self.reportFiles(since: start.addingTimeInterval(-60)).filter { !handled.contains($0.lastPathComponent) }
        let stamp = Self.fileStamp.string(from: Date())
        let work = FileManager.default.temporaryDirectory.appending(path: "Ikago Crash Report \(stamp)")
        try? FileManager.default.removeItem(at: work)
        do {
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            try Self.scrub(summary(previous: previous, files: files)).write(to: work.appending(path: "Summary.txt"), atomically: true, encoding: .utf8)
            for file in files {
                guard var text = try? String(contentsOf: file, encoding: .utf8) else { continue }
                if file.lastPathComponent.hasPrefix("JetsamEvent") { text = Self.trimJetsam(text) }
                try Self.scrub(text).write(to: work.appending(path: file.lastPathComponent), atomically: true, encoding: .utf8)
            }
            let zip = work.appendingPathExtension("zip")
            try? FileManager.default.removeItem(at: zip)
            let ditto = Process()
            ditto.executableURL = URL(filePath: "/usr/bin/ditto")
            ditto.arguments = ["-c", "-k", "--keepParent", work.path, zip.path]
            try ditto.run(); ditto.waitUntilExit()
            guard ditto.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
            DownloadCenter.shared.save(try Data(contentsOf: zip), suggestedFilename: zip.lastPathComponent, sourceURL: nil)
            try? FileManager.default.removeItem(at: zip)
            try? FileManager.default.removeItem(at: work)
            if previous != nil { markHandled(files) }
            if reveal, let item = DownloadCenter.shared.items.first { DownloadCenter.shared.reveal(item) }
            return true
        } catch {
            try? FileManager.default.removeItem(at: work)
            if reveal {
                let alert = NSAlert()
                alert.messageText = "Ikago couldn’t save a crash report"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
            return false
        }
    }

    private func summary(previous: Marker?, files: [URL]) -> String {
        var lines = ["Ikago crash report", "Saved \(Date().formatted(.iso8601))", ""]
        if let previous {
            lines += ["The last run of Ikago ended unexpectedly.",
                      "Version: \(previous.version), engine: \(previous.engine)",
                      "Started: \(previous.started.formatted(.iso8601)), last seen: \(previous.updated.formatted(.iso8601))",
                      "Last thing Ikago noted: \(previous.lastEvent)",
                      "Then: \(previous.tabs) tabs, \(previous.windows) \(previous.windows == 1 ? "window" : "windows"), \(previous.memoryMB) MB memory"]
        } else {
            lines += ["Saved from Help ▸ Save Crash Report (reports from the last 7 days)."]
        }
        let memory = ProcessInfo.processInfo.physicalMemory / 1_073_741_824
        lines += ["", "This Ikago: \(Self.version), macOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
                  "Mac: \(Self.model), \(memory) GB memory", "",
                  files.isEmpty ? "macOS wrote no crash report for it (it can lose one when the Mac is short on memory)."
                                : "Reports included:\n" + files.map { "  \($0.lastPathComponent)" }.joined(separator: "\n"),
                  "", "Home folder, user and Mac names are replaced. Nothing was sent: pass this file on yourself."]
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Finding and cleaning reports

    private static func reportFiles(since start: Date) -> [URL] {
        let user = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/DiagnosticReports")
        let system = URL(filePath: "/Library/Logs/DiagnosticReports")
        var found: [URL] = []
        for folder in [user, system] {
            let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey])) ?? []
            for url in items {
                let name = url.lastPathComponent
                // Ikago and its Chromium helpers, plus memory kills, which name every process and say why one was ended.
                guard name.hasPrefix("Ikago") || name.hasPrefix("JetsamEvent") else { continue }
                guard ["ips", "hang", "diag", "spin", "crash"].contains(url.pathExtension) else { continue }
                // macOS touches older reports again later, so their creation date is the one that says when.
                let date = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                if date >= start { found.append(url) }
            }
        }
        return found.sorted { $0.lastPathComponent < $1.lastPathComponent }.suffix(20)
    }

    /// A JetsamEvent lists every process on the Mac. Keep the memory totals, Ikago's processes and the ten largest.
    private static func trimJetsam(_ text: String) -> String {
        let parts = text.split(separator: "\n", maxSplits: 1).map(String.init)
        guard parts.count == 2, var body = (try? JSONSerialization.jsonObject(with: Data(parts[1].utf8))) as? [String: Any],
              let processes = body["processes"] as? [[String: Any]] else { return text }
        let pages = { (process: [String: Any]) in process["rpages"] as? Int ?? 0 }
        let largest = processes.sorted { pages($0) > pages($1) }.prefix(10)
        let ikago = processes.filter { ($0["name"] as? String ?? "").hasPrefix("Ikago") || $0["reason"] != nil }
        var kept: [[String: Any]] = []
        for process in Array(largest) + ikago where !kept.contains(where: { $0["pid"] as? Int == process["pid"] as? Int }) {
            kept.append(process.filter { ["name", "pid", "rpages", "lifetimeMax", "reason", "states", "coalition", "cpuTime"].contains($0.key) })
        }
        body["processes"] = kept
        body["note"] = "Trimmed by Ikago: the ten largest processes, Ikago's own and any that were ended (of \(processes.count))."
        guard let data = try? JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted, .sortedKeys]) else { return text }
        return parts[0] + "\n" + String(decoding: data, as: UTF8.self)
    }

    private static func scrub(_ text: String) -> String {
        var text = text
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        // Reports are JSON, which writes "/" as "\\/".
        var names = [(home, "~"), (home.replacingOccurrences(of: "/", with: "\\/"), "~"), (NSUserName(), "<user>")]
        if !NSFullUserName().isEmpty { names.append((NSFullUserName(), "<user>")) }
        for host in [Host.current().localizedName, ProcessInfo.processInfo.hostName.components(separatedBy: ".").first] {
            if let host, host.count > 2 { names.append((host, "<mac>")); names.append((host.replacingOccurrences(of: " ", with: "-"), "<mac>")) }
        }
        for (name, replacement) in names where name.count > 2 { text = text.replacingOccurrences(of: name, with: replacement) }
        return text
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }

    private static var model: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var bytes = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &bytes, &size, nil, 0)
        return String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private static func footprintMB() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return result == KERN_SUCCESS ? Int(info.phys_footprint / 1_048_576) : 0
    }

    private static let fileStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm"
        return formatter
    }()
}

private extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
