import AppKit
import WebKit
import IKCEFBridge

/// Owns live WebKit downloads and persistent download history.
@MainActor
@Observable
final class DownloadCenter: NSObject {
    static let shared = DownloadCenter()
    struct Item: Identifiable, Codable, Equatable, Sendable {
        var id = UUID()
        var name = "Download"
        var sourceURL: URL?
        var fileURL: URL?
        var received: Int64 = 0
        var total: Int64 = 0
        var finished = false
        var failed = false
        var cancelled = false
        var interrupted = false
        var startedAt = Date()
        var completedAt: Date?
        var errorDescription: String?
        var inProgress: Bool { !finished && !failed && !cancelled && !interrupted }
        var fraction: Double { total > 0 ? min(1, max(0, Double(received) / Double(total))) : 0 }
    }

    @ObservationIgnored private var privateDownloads: Set<UUID> = []
    @ObservationIgnored private var cefIDs: [String: UUID] = [:]
    @ObservationIgnored private var cefCancels: [UUID: () -> Void] = [:]
    private(set) var items: [Item] = [] { didSet { syncToolbarButton() } }
    private(set) var historyError: String?
    var activeCount: Int { items.filter(\.inProgress).count }
    var overallFraction: Double? {
        let active = items.filter(\.inProgress)
        guard !active.isEmpty, active.allSatisfy({ $0.total > 0 }) else { return nil }
        let total = active.reduce(0.0) { $0 + Double($1.total) }
        return min(1, active.reduce(0.0) { $0 + Double($1.received) } / total)
    }
    @ObservationIgnored private var visibilityDate = Date() { didSet { syncToolbarButton() } }
    @ObservationIgnored private var dismissedToolbarItems: Set<UUID> = [] { didSet { syncToolbarButton() } }
    /// Stored, and written only when it flips, so the toolbars that read it don't re-render on every byte of progress.
    private(set) var showsToolbarButton = false
    private func syncToolbarButton() {
        let shows = shouldShowToolbarButton(at: visibilityDate)
        if shows != showsToolbarButton { showsToolbarButton = shows }
    }
    func shouldShowToolbarButton(at date: Date) -> Bool {
        items.contains { $0.inProgress || (!dismissedToolbarItems.contains($0.id) && date.timeIntervalSince($0.completedAt ?? $0.startedAt) < 86_400) }
    }

    /// Dismiss the automatic control without clearing history or hiding live progress.
    /// A new download makes it visible again; user-placed controls remain permanent.
    func dismissToolbarButton() { dismissedToolbarItems = Set(items.map(\.id)) }

    @ObservationIgnored private let openFile: (URL) -> Bool
    @ObservationIgnored private let history: DownloadHistoryStore
    @ObservationIgnored private var downloads: [UUID: WKDownload] = [:]
    @ObservationIgnored private var itemIDs: [ObjectIdentifier: UUID] = [:]
    @ObservationIgnored private var observations: [ObjectIdentifier: [NSKeyValueObservation]] = [:]
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var expirationTask: Task<Void, Never>?
    /// The latest byte counts per download, applied at most ten times a second.
    @ObservationIgnored private var pendingProgress: [ObjectIdentifier: (done: Int64, total: Int64)] = [:]

    init(history: DownloadHistoryStore = .standard, openFile: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }) {
        self.openFile = openFile
        self.history = history
        items = history.load().map { item in
            var item = item
            if item.inProgress { item.interrupted = true; item.errorDescription = "Ikago closed before this download finished." }
            return item
        }
        super.init()
        trimHistory(); refreshButtonVisibility()
        IKCEFDownloads.shared.destinationHandler = { [weak self] identifier, name, source, ephemeral in
            MainActor.assumeIsolated {
                guard let self else { return nil }
                var item = Item()
                let url = self.uniqueURL(for: name)
                item.name = url.lastPathComponent; item.fileURL = url; item.sourceURL = URL(string: source)
                self.cefIDs[identifier] = item.id
                if ephemeral { self.privateDownloads.insert(item.id) }
                self.items.insert(item, at: 0); self.saveNow()
                return url.path
            }
        }
        IKCEFDownloads.shared.eventHandler = { [weak self] snapshot, cancel in
            MainActor.assumeIsolated { self?.cefUpdated(snapshot, cancel: cancel) }
        }
    }

    func track(_ download: WKDownload, isPrivate: Bool = false) {
        let key = ObjectIdentifier(download)
        guard itemIDs[key] == nil else { return }
        download.delegate = self
        var item = Item(); item.sourceURL = download.originalRequest?.url
        if isPrivate { privateDownloads.insert(item.id) }
        if let name = item.sourceURL?.lastPathComponent, !name.isEmpty { item.name = name }
        items.insert(item, at: 0)
        itemIDs[key] = item.id; downloads[item.id] = download
        let report: @Sendable (Progress, NSKeyValueObservedChange<Int64>) -> Void = { [weak self] (p: Progress, _: NSKeyValueObservedChange<Int64>) in
            let done = max(0, p.completedUnitCount), total = max(0, p.totalUnitCount)
            Task { @MainActor [weak self] in self?.queueProgress(key, done: done, total: total) }
        }
        observations[key] = [download.progress.observe(\.completedUnitCount, options: [.initial, .new], changeHandler: report),
                             download.progress.observe(\.totalUnitCount, options: [.new], changeHandler: report)]
        trimHistory(); saveNow()
    }

    /// Saves bytes WebKit hands over directly (the PDF viewer's download button) as a finished download.
    func save(_ data: Data, suggestedFilename: String, sourceURL: URL?, isPrivate: Bool = false) {
        let url = uniqueURL(for: suggestedFilename)
        var item = Item(); item.sourceURL = sourceURL; item.fileURL = url; item.name = url.lastPathComponent
        if isPrivate { privateDownloads.insert(item.id) }
        do {
            try data.write(to: url, options: .atomic)
            item.received = Int64(data.count); item.total = item.received; item.finished = true
        } catch {
            item.failed = true; item.errorDescription = error.localizedDescription
        }
        item.completedAt = Date()
        items.insert(item, at: 0)
        trimHistory(); saveNow()
    }

    private func cefUpdated(_ snapshot: [AnyHashable: Any], cancel: @escaping () -> Void) {
        guard let key = snapshot["id"] as? String, let id = cefIDs[key],
              let index = items.firstIndex(where: { $0.id == id }) else { return }
        cefCancels[id] = cancel
        items[index].received = (snapshot["received"] as? NSNumber)?.int64Value ?? 0
        items[index].total = (snapshot["total"] as? NSNumber)?.int64Value ?? 0
        items[index].finished = snapshot["complete"] as? Bool ?? false
        items[index].cancelled = snapshot["cancelled"] as? Bool ?? false
        items[index].interrupted = snapshot["interrupted"] as? Bool ?? false
        if !items[index].inProgress {
            items[index].completedAt = Date()
            if items[index].interrupted { items[index].errorDescription = "Chromium interrupted this download (\(snapshot["reason"] ?? 0))." }
            cefCancels[id] = nil; cefIDs[key] = nil
            saveNow()
        } else { scheduleSave() }
    }
    func cancel(_ id: UUID) {
        if let cancel = cefCancels[id] { cancel(); return }
        guard let download = downloads[id] else { return }
        finish(download) { $0.cancelled = true }
        download.cancel { _ in }
    }
    func reveal(_ item: Item) {
        guard let url = item.fileURL, url.isFileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    @discardableResult
    func open(_ item: Item) -> Bool {
        guard let url = item.fileURL, url.isFileURL, item.finished,
              FileManager.default.fileExists(atPath: url.path) else { return false }
        return openFile(url)
    }
    func clearFinished() { items.removeAll { !$0.inProgress }; saveNow(); history.discardBackup() }
    func remove(_ id: UUID) { items.removeAll { $0.id == id && !$0.inProgress }; saveNow(); history.discardBackup() }
    func revealDownloadsFolder() { NSWorkspace.shared.open(Self.downloadsFolder) }

    func saveNow() {
        refreshButtonVisibility()
        saveTask?.cancel(); saveTask = nil
        do { try history.save(items.filter { !privateDownloads.contains($0.id) }); historyError = nil }
        catch { historyError = "Download history couldn’t be saved." }
    }
    private func refreshButtonVisibility() {
        expirationTask?.cancel(); expirationTask = nil
        visibilityDate = Date()
        let deadlines = items.filter { !$0.inProgress }.map { ($0.completedAt ?? $0.startedAt).addingTimeInterval(86_400) }
        guard let next = deadlines.filter({ $0 > visibilityDate }).min() else { return }
        let delay = next.timeIntervalSince(visibilityDate)
        expirationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.refreshButtonVisibility()
        }
    }
    private func scheduleSave() {
        guard saveTask == nil else { return }
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self else { return }
            self.saveTask = nil; self.saveNow()
        }
    }
    private func trimHistory() {
        var remaining = max(0, 1000 - activeCount)
        items = items.filter { item in
            if item.inProgress { return true }
            guard remaining > 0 else { return false }
            remaining -= 1; return true
        }
    }
    private static var downloadsFolder: URL {
        if WebProfiles.isTestMode {
            let dir = SessionStore.testDirectory.appending(path: "Downloads")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }
        return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    }
    /// Coalesces WebKit's progress callbacks (one per network read) into one update per 100 ms.
    private func queueProgress(_ key: ObjectIdentifier, done: Int64, total: Int64) {
        let scheduled = pendingProgress[key] != nil
        pendingProgress[key] = (done, total)
        guard !scheduled else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard let self, let value = self.pendingProgress.removeValue(forKey: key) else { return }
            self.update(key) { $0.received = max($0.received, value.done); if value.total > 0 { $0.total = value.total } }
            self.scheduleSave()
        }
    }

    private func update(_ key: ObjectIdentifier, _ change: (inout Item) -> Void) {
        guard let id = itemIDs[key], let index = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[index])
    }
    private func finish(_ download: WKDownload, _ change: (inout Item) -> Void) {
        let key = ObjectIdentifier(download)
        guard let id = itemIDs[key] else { return }
        update(key) { item in
            item.received = max(item.received, max(0, download.progress.completedUnitCount))
            change(&item); item.completedAt = Date()
        }
        downloads[id] = nil; observations[key] = nil; itemIDs[key] = nil
        trimHistory(); saveNow()
    }
    private func uniqueURL(for suggested: String) -> URL {
        let leaf = (suggested as NSString).lastPathComponent
        let name = leaf.isEmpty || leaf == "." || leaf == ".." ? "download" : leaf
        let base = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
        let reserved = Set(items.filter(\.inProgress).compactMap(\.fileURL))
        var candidate = Self.downloadsFolder.appending(path: name), n = 2
        while FileManager.default.fileExists(atPath: candidate.path) || reserved.contains(candidate) {
            candidate = Self.downloadsFolder.appending(path: ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"); n += 1
        }
        return candidate
    }
}

extension DownloadCenter: WKDownloadDelegate {
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        guard itemIDs[ObjectIdentifier(download)] != nil else { return nil }
        let url = uniqueURL(for: suggestedFilename)
        update(ObjectIdentifier(download)) {
            $0.fileURL = url; $0.name = url.lastPathComponent
            if response.expectedContentLength > 0 { $0.total = response.expectedContentLength }
        }
        saveNow(); return url
    }
    func downloadDidFinish(_ download: WKDownload) {
        finish(download) { item in
            if let path = item.fileURL?.path, let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size]) as? NSNumber {
                item.received = size.int64Value
            }
            if item.received == 0 { item.received = item.total }
            item.total = item.received; item.finished = true
        }
    }
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        finish(download) {
            if (error as NSError).domain == NSURLErrorDomain, (error as NSError).code == NSURLErrorCancelled { $0.cancelled = true }
            else { $0.failed = true; $0.errorDescription = error.localizedDescription }
        }
    }
}
