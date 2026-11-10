import AppKit
import CryptoKit

/// Persistent cache with bounded memory; no third-party favicon service and no cookies on requests.
@MainActor
final class FaviconCache {
    static let shared = FaviconCache()
    private let images = NSCache<NSString, NSImage>()
    /// The bytes each image was decoded from, so page/site copies store the original format, not TIFF.
    let originals = NSCache<NSString, NSData>()
    /// Page/site key → the icon URL last stored under it, so an unchanged icon isn't sealed and written again.
    var storedIcons: [String: String] = [:]
    /// Keys with no file on disk, so rows without icons don't read the disk on every render.
    private var misses: Set<String> = []
    /// Images whose sealed file is still being written, so an evicted entry isn't mistaken for a miss.
    private var writing: [String: (token: Int, image: NSImage)] = [:]
    private var writeToken = 0
    /// Sealing and writing happen here, in order, off the main thread.
    private static let writer = DispatchQueue(label: "app.ikago.favicons.write", qos: .utility)
    private var pending: [URL: Task<NSImage?, Never>] = [:]
    private let session: URLSession
    private let directory: URL
    private var generation = 0

    private init() {
        images.countLimit = 256
        originals.countLimit = 256
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 10
        session = URLSession(configuration: configuration)
        directory = (WebProfiles.isTestMode ? SessionStore.testDirectory
                     : AppIdentity.dataDirectory)
            .appending(path: "Favicons")
    }

    /// `persist: false` (private windows) keeps the icon in memory only, so no trace reaches the disk.
    func image(for url: URL, persist: Bool = true) async -> NSImage? {
        let scheme = url.scheme?.lowercased() ?? ""
        // HTTPS-only mode covers the browser's own requests too.
        guard scheme == "https" || (scheme == "http" && !BrowserSecurity.shared.requiresHTTPS(url)) else { return nil }
        if let image = cachedImage(for: url) { return image }
        if let task = pending[url] { return await task.value }
        let stamp = generation
        let task = Task<NSImage?, Never> { [self, session] in
            // The download runs off the main thread; only decoding a validated, bounded icon happens here.
            let download = Task.detached(priority: .utility) { await Self.download(url, session: session) }
            let data = await withTaskCancellationHandler { await download.value } onCancel: { download.cancel() }
            guard let data, !Task.isCancelled, stamp == generation, let image = NSImage(data: data),
                  image.size.width <= 4096, image.size.height <= 4096 else { return nil }
            originals.setObject(data as NSData, forKey: url.absoluteString as NSString)
            if persist { storeCached(image, data: data, key: url.absoluteString) }
            else { images.setObject(image, forKey: url.absoluteString as NSString) }
            return image
        }
        pending[url] = task
        let image = await task.value
        if stamp == generation { pending[url] = nil }
        return image
    }

    /// Fetches at most 1 MB without cookies; nil for errors, other statuses and formats icons don't use.
    nonisolated private static func download(_ url: URL, session: URLSession) async -> Data? {
        let limit = 1_048_576
        guard let (bytes, response) = try? await session.bytes(from: url),
              let response = response as? HTTPURLResponse, response.statusCode == 200,
              response.expectedContentLength <= Int64(limit) else { return nil }
        // Bound memory even if a server sends a large or unbounded response.
        var data = Data()
        data.reserveCapacity(max(0, Int(response.expectedContentLength)))
        do {
            for try await byte in bytes {
                guard data.count < limit else { return nil }
                data.append(byte)
            }
        } catch { return nil }
        // Reduced off the main thread: a huge icon never reaches the cache, the disk or a main-thread decode.
        return normalized(data)
    }

    /// This decodes in the unsandboxed main process, so only formats sites really use for icons
    /// reach the system's image parsers, not PDF, TIFF, EPS and the rest.
    nonisolated static func isFaviconFormat(_ data: Data) -> Bool {
        let bytes = [UInt8](data.prefix(16))
        func starts(_ prefix: [UInt8]) -> Bool { bytes.starts(with: prefix) }
        if starts([0x89, 0x50, 0x4E, 0x47]) || starts([0xFF, 0xD8, 0xFF]) || starts([0x47, 0x49, 0x46, 0x38])
            || starts([0x00, 0x00, 0x01, 0x00]) || starts([0x42, 0x4D]) { return true }  // PNG, JPEG, GIF, ICO, BMP
        if bytes.count >= 12, starts([0x52, 0x49, 0x46, 0x46]), Array(bytes[8..<12]) == Array("WEBP".utf8) { return true }
        // SVG is text, and its renderer runs no scripts.
        let text = String(decoding: data.prefix(1024), as: UTF8.self).drop { $0.isWhitespace || $0 == "\u{FEFF}" }.lowercased()
        return text.hasPrefix("<svg") || (text.hasPrefix("<?xml") && text.contains("<svg")) || (text.hasPrefix("<!--") && text.contains("<svg"))
    }

    nonisolated static func file(for key: String, in directory: URL) -> URL {
        let hash = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appending(path: hash)
    }

    func file(for key: String) -> URL {
        Self.file(for: key, in: directory)
    }

    func readCached(key: String) -> NSImage? {
        let identity = key as NSString
        if let image = images.object(forKey: identity) { return image }
        if let image = writing[key]?.image { return image }
        if misses.contains(key) { return nil }
        let destination = file(for: key)
        if let raw = try? Data(contentsOf: destination), let data = try? SealedStorage.open(raw),
           let image = NSImage(data: data) {
            images.setObject(image, forKey: identity)
            originals.setObject(data as NSData, forKey: identity)
            return image
        }
        if misses.count >= 4096 { misses.removeAll() }
        misses.insert(key)
        return nil
    }

    /// Memory only, never the disk: the icon URL, then the page, then its site, like `cachedImage(pageURL:iconURL:)`.
    func memoryImage(pageURL: String, iconURL: URL?) -> NSImage? {
        func memory(_ key: String) -> NSImage? { images.object(forKey: key as NSString) ?? writing[key]?.image }
        if let iconURL, let image = memory(iconURL.absoluteString) { return image }
        guard Self.hasOwnIcon(pageURL) else { return nil }
        return memory("page:" + pageURL) ?? memory("site:" + Self.siteKey(pageURL))
    }

    func storeCached(_ image: NSImage, data: Data, key: String) {
        images.setObject(image, forKey: key as NSString)
        originals.setObject(data as NSData, forKey: key as NSString)
        misses.remove(key)
        writeToken += 1
        let token = writeToken, directory = directory
        writing[key] = (token, image)
        Self.writer.async {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            // Icons reveal which sites were visited, so they're encrypted like history. Never written in plain text.
            if let sealed = try? SealedStorage.seal(data) {
                try? sealed.write(to: Self.file(for: key, in: directory), options: .atomic)
            }
            Task { @MainActor in FaviconCache.shared.finishWrite(key, token: token) }
        }
    }

    private func finishWrite(_ key: String, token: Int) {
        if writing[key]?.token == token { writing[key] = nil }
    }

    /// Encrypts icons saved before encryption existed, off the main thread. Runs once per launch and is
    /// a quick scan when there's nothing left to do.
    func encryptExistingFiles() {
        let directory = directory
        Task.detached(priority: .utility) {
            let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            for file in files {
                guard let handle = try? FileHandle(forReadingFrom: file) else { continue }
                let head = (try? handle.read(upToCount: 8)) ?? Data()
                try? handle.close()
                guard !SealedStorage.isSealed(head), let data = try? Data(contentsOf: file), let sealed = try? SealedStorage.seal(data) else { continue }
                try? sealed.write(to: file, options: .atomic)
            }
            FaviconCache.shrinkStoredFiles(in: directory)
        }
    }

    func clear() {
        generation += 1
        pending.values.forEach { $0.cancel() }
        pending.removeAll()
        images.removeAllObjects()
        originals.removeAllObjects()
        storedIcons.removeAll()
        misses.removeAll()
        writing.removeAll()
        // Waits for queued writes, so none can recreate a file after the folder is gone.
        let directory = directory
        Self.writer.sync { try? FileManager.default.removeItem(at: directory) }
    }

}
