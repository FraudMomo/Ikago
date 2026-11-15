import Foundation

/// Public phishing lists, downloaded to this Mac and matched locally, so browsing is never sent to anyone.
/// Hosts are kept as sorted 64-bit hashes: about 2 MB for 240,000 entries. Both engines use them; on
/// WebKit they add to Apple's own fraud warnings.
@MainActor
final class ThreatHosts {
    static let shared = ThreatHosts()

    struct Feed: Sendable {
        let file: String, url: URL, interval: TimeInterval, minimumEntries: Int
    }
    /// phishunt.io (CC0, new sites hourly) and PhishDestroy's curated list (MIT, longer memory).
    nonisolated static let feeds = [
        Feed(file: "phishunt.bin", url: URL(string: "https://phishunt.io/blocklist/domains.txt")!, interval: 6 * 3600, minimumEntries: 50),
        Feed(file: "destroylist.bin", url: URL(string: "https://raw.githubusercontent.com/phishdestroy/destroylist/main/list.txt")!, interval: 24 * 3600, minimumEntries: 10_000),
    ]
    private nonisolated static let maxDownload = 24 * 1024 * 1024

    private(set) var hashes: [UInt64] = []
    private(set) var lastUpdated: Date?
    private var refreshTask: Task<Void, Never>?

    private var directory: URL {
        (WebProfiles.isTestMode ? SessionStore.testDirectory : AppIdentity.dataDirectory).appending(path: "Safety", directoryHint: .isDirectory)
    }

    func contains(_ host: String) -> Bool {
        var labels = host.lowercased().split(separator: ".")
        while labels.count >= 2 {
            let candidate = labels.joined(separator: ".")
            if Self.search(hashes, Self.hash(candidate)) {
                // A list entry must never break a famous site, whatever the list says.
                return !SiteSafetyRules.protected.contains(SiteSafetyRules.registrable(host))
            }
            labels.removeFirst()
        }
        return false
    }

    /// Loads what's on disk, then keeps the lists fresh for as long as the app runs.
    func start() {
        guard refreshTask == nil, !WebProfiles.isTestMode else { return }
        reload()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(3600))
            }
        }
    }

    func refresh() async {
        let directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var changed = false
        for feed in Self.feeds {
            let file = directory.appending(path: feed.file)
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, Date().timeIntervalSince(modified) < feed.interval { continue }
            // A failed download or a suspiciously short list keeps the previous copy.
            if await Self.download(feed, to: file) { changed = true }
        }
        if changed { reload() }
    }

    private func reload() {
        var merged: [UInt64] = []
        var newest: Date?
        for feed in Self.feeds {
            let file = directory.appending(path: feed.file)
            guard let data = try? Data(contentsOf: file), data.count % 8 == 0 else { continue }
            merged += data.withUnsafeBytes { Array($0.bindMemory(to: UInt64.self)) }
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, modified > (newest ?? .distantPast) { newest = modified }
        }
        merged.sort()
        hashes = merged
        lastUpdated = newest
    }

    private nonisolated static func download(_ feed: Feed, to file: URL) async -> Bool {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForResource = 120
        configuration.httpAdditionalHeaders = ["User-Agent": "Ikago"]
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        guard let (data, response) = try? await session.data(from: feed.url), (response as? HTTPURLResponse)?.statusCode == 200,
              data.count <= maxDownload else { return false }
        let entries = parse(data)
        guard entries.count >= feed.minimumEntries else { return false }
        let bytes = entries.withUnsafeBytes { Data($0) }
        return (try? bytes.write(to: file, options: .atomic)) != nil
    }

    /// One domain per line. Anything else (comments, junk, an error page) is skipped.
    nonisolated static func parse(_ data: Data) -> [UInt64] {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-.")
        var entries: [UInt64] = []
        for line in String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline) {
            let host = line.trimmingCharacters(in: .whitespaces).lowercased()
            guard host.count <= 253, host.contains("."), !host.hasPrefix("."), !host.hasSuffix("."), host.allSatisfy(allowed.contains) else { continue }
            entries.append(hash(host))
        }
        return entries.sorted()
    }

    /// FNV-1a: not for secrecy, only a compact key. A false match needs a 64-bit collision.
    nonisolated static func hash(_ text: String) -> UInt64 {
        var value: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 { value = (value ^ UInt64(byte)) &* 0x100000001b3 }
        return value
    }

    nonisolated static func search(_ sorted: [UInt64], _ value: UInt64) -> Bool {
        var low = 0, high = sorted.count - 1
        while low <= high {
            let middle = (low + high) / 2
            if sorted[middle] == value { return true }
            if sorted[middle] < value { low = middle + 1 } else { high = middle - 1 }
        }
        return false
    }

    #if DEBUG
    func useForTesting(_ hosts: [String]) { hashes = hosts.map(Self.hash).sorted() }
    #endif
}
