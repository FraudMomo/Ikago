import AppKit
import Observation

/// Safari web extensions inside the apps on this Mac, kept current: the app folders are watched, so an app installed
/// from the App Store (or dragged in, or deleted) shows up in Settings within a moment.
@MainActor @Observable
final class SafariExtensionScanner {
    static let shared = SafariExtensionScanner()

    struct Found: Identifiable, Equatable {
        /// Web extensions are what WebKit can run. Safari app extensions (native code hosted by Safari) and content
        /// blockers are Safari's own systems: they're listed so a new app never seems to be missed, but can't be turned on.
        enum Kind: Equatable { case web, safariOnly, contentBlocker }
        let appex: URL
        let app: URL
        let name: String
        var kind = Kind.web
        var id: String { appex.path }
    }

    private(set) var found: [Found] = []
    @ObservationIgnored private var sources: [DispatchSourceFileSystemObject] = []
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var watching = false

    nonisolated static var applicationFolders: [URL] {
        [URL(fileURLWithPath: "/Applications"), FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications")]
    }
    /// The folders searched and watched (checks use a temporary one).
    @ObservationIgnored let roots: [URL]

    init(roots: [URL] = SafariExtensionScanner.applicationFolders) { self.roots = roots }

    /// Starts watching (once) and scans now.
    func start() {
        rescan()
        guard !watching else { return }
        watching = true
        for root in roots { watch(root) }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.rescan() }
        }
    }

    /// A short pause first: an installer writes an app in several steps.
    func rescan(after delay: Duration = .zero) {
        pending?.cancel()
        pending = Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            let roots = self?.roots ?? []
            let found = await Task.detached(priority: .utility) { Self.scan(roots) }.value
            guard !Task.isCancelled, let self, found != self.found else { return }
            self.found = found
        }
    }

    private func watch(_ folder: URL) {
        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.rescan(after: .seconds(1)) } }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        sources.append(source)
    }

    /// Apps in the two Applications folders and one folder down (Utilities, Setapp and the like).
    nonisolated static func scan(_ roots: [URL]) -> [Found] {
        let fm = FileManager.default
        var apps: [URL] = []
        for root in roots {
            for item in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? [] {
                if item.pathExtension == "app" { apps.append(item); continue }
                guard (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
                apps += ((try? fm.contentsOfDirectory(at: item, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? [])
                    .filter { $0.pathExtension == "app" }
            }
        }
        var found: [Found] = []
        for app in apps {
            let plugIns = app.appending(path: "Contents/PlugIns")
            for appex in (try? fm.contentsOfDirectory(at: plugIns, includingPropertiesForKeys: nil)) ?? [] where appex.pathExtension == "appex" {
                let info = NSDictionary(contentsOf: appex.appending(path: "Contents/Info.plist"))
                let kind: Found.Kind
                switch (info?["NSExtension"] as? [String: Any])?["NSExtensionPointIdentifier"] as? String {
                case "com.apple.Safari.web-extension": kind = .web
                case "com.apple.Safari.extension": kind = .safariOnly
                case "com.apple.Safari.content-blocker": kind = .contentBlocker
                default: continue
                }
                let appName = app.deletingPathExtension().lastPathComponent
                var name = (info?["CFBundleDisplayName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? appName
                if name.hasSuffix(" Extension"), name.count > 10 { name = String(name.dropLast(10)) }  // "uBlock Origin Lite Extension"
                found.append(Found(appex: appex, app: app, name: name, kind: kind))
            }
        }
        // Ones Ikago can run first, then Safari's own kinds.
        return found.sorted { ($0.kind == .web ? 0 : 1, $0.name.lowercased()) < ($1.kind == .web ? 0 : 1, $1.name.lowercased()) }
    }
}
