import AppKit
import Security

/// Keeps Ikago's data in its app group container, which macOS locks to apps signed by the same team.
/// Other apps you run are denied, so they can't copy cookies, site storage, caches or Chromium profiles
/// (only apps you gave Full Disk Access still can). WebKit has no public way to choose its folders,
/// so its per-app folders become symbolic links into the container. macOS checks the real path, so a
/// link is no way around the lock. Encryption (`SealedStorage`) still covers history and sessions.
enum ProtectedStorage {
    static let groupSuffix = "." + AppIdentity.bundleID
    /// The Default Space's WebKit store. WebKit's built-in default store keeps its cookies in a file
    /// directly in ~/Library/HTTPStorages, a shared folder that can't be linked, so Default uses this.
    static let defaultStoreID = UUID(uuidString: "1CA9D3FA-0000-4000-8000-00000000D3FA")!
    static let markerName = ".protected-container"

    enum Status: Equatable {
        case protected, unavailable(String)
    }
    nonisolated(unsafe) private(set) static var status = Status.unavailable("Not checked yet.")
    static var isProtected: Bool { status == .protected }

    /// The team-prefixed group this build is signed for, or nil for ad hoc builds. Asking macOS for a
    /// container the signature doesn't cover would raise a prompt, so the entitlement is checked first.
    static let groupID: String? = {
        guard let task = SecTaskCreateFromSelf(nil),
              let groups = SecTaskCopyValueForEntitlement(task, "com.apple.security.application-groups" as CFString, nil) as? [String],
              let team = teamID else { return nil }
        return groups.first { $0 == team + groupSuffix }
    }()
    static let container: URL? = groupID.flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }

    private static var teamID: String? {
        var code: SecCode?, staticCode: SecStaticCode?, info: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess
        else { return nil }
        return (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
    }

    struct Failure: LocalizedError {
        let errorDescription: String?
    }

    /// Runs once at launch, before anything opens a store. Throws only when the data was moved into
    /// the container and this copy of Ikago can't open it, which must never look like lost data.
    static func prepare(home: URL = FileManager.default.homeDirectoryForCurrentUser) throws {
        // Ikago's own requests use ephemeral sessions. Never touch HTTPCookieStorage.shared: it is the
        // built-in default store's cookie file in ~/Library/HTTPStorages, and merely configuring it loads
        // those cookies and writes them back there at quit. The shared cache stays in memory too.
        URLCache.shared = URLCache(memoryCapacity: 8 << 20, diskCapacity: 0)
        if isOnlyInstance { removeTemporaryFiles() }
        let library = Library(home: home)
        guard let container else {
            if FileManager.default.fileExists(atPath: library.support.appending(path: markerName).path) {
                throw Failure(errorDescription: "Your data is in Ikago’s protected storage, and this copy of Ikago isn’t signed to open it.")
            }
            try? adoptDefaultStore(library)
            status = .unavailable("This copy of Ikago isn’t signed with a developer certificate, so macOS can’t lock its data to it.")
            return
        }
        let issues = migrate(library, into: container)
        status = issues.isEmpty ? .protected : .unavailable(issues.joined(separator: " "))
        if !issues.isEmpty { NSLog("Ikago protected storage: %@", issues.joined(separator: " ")) }
    }

    /// Where every Ikago folder lives in a home folder. Checks pass a disposable one.
    struct Library {
        let root: URL
        init(home: URL) { root = home.appending(path: "Library", directoryHint: .isDirectory) }
        var support: URL { AppIdentity.supportDirectory(home: root.deletingLastPathComponent()) }
        var webKit: URL { root.appending(path: "WebKit/" + AppIdentity.bundleID, directoryHint: .isDirectory) }
        var caches: URL { root.appending(path: "Caches/" + AppIdentity.bundleID, directoryHint: .isDirectory) }
        var httpStorage: URL { root.appending(path: "HTTPStorages/" + AppIdentity.bundleID, directoryHint: .isDirectory) }
        var httpStorages: URL { root.appending(path: "HTTPStorages", directoryHint: .isDirectory) }
        /// Chromium maps a profile in Application Support to a cache folder here.
        var chromiumCache: URL { root.appending(path: "Caches/Ikago", directoryHint: .isDirectory) }
    }

    /// Moves everything in, links WebKit's folders and returns what couldn't be done. Never overwrites:
    /// a name present in both places stays where it is and is reported, so nothing is lost.
    static func migrate(_ library: Library, into container: URL) -> [String] {
        let files = FileManager.default
        var issues: [String] = []
        let data = container.appending(path: "Ikago", directoryHint: .isDirectory)
        do {
            try files.createDirectory(at: data, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            if files.fileExists(atPath: library.support.path) {
                // The updater runs outside Ikago and can't enter the container; its folder holds no browsing data.
                let kept: Set<String> = ["Updates", markerName, ".migrated-from-earlier-identity"]
                for name in try files.contentsOfDirectory(atPath: library.support.path) where !kept.contains(name) {
                    issues += move(library.support.appending(path: name), to: data.appending(path: name))
                }
            }
            for (link, name) in [(library.webKit, "WebKit"), (library.caches, "Caches"), (library.httpStorage, "HTTPStorages")] {
                issues += self.link(link, to: container.appending(path: name, directoryHint: .isDirectory))
            }
            try adoptDefaultStore(library)
            // Only a cache, rebuilt inside each profile now that the profiles are in the container.
            try? files.removeItem(at: library.chromiumCache.appending(path: "Chromium"))
            if (try? files.contentsOfDirectory(atPath: library.chromiumCache.path))?.isEmpty == true {
                try? files.removeItem(at: library.chromiumCache)
            }
            try files.createDirectory(at: library.support, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try Data().write(to: library.support.appending(path: markerName))
        } catch { issues.append(error.localizedDescription) }
        return issues
    }

    private static func move(_ source: URL, to destination: URL) -> [String] {
        let files = FileManager.default
        guard files.fileExists(atPath: source.path) || isLink(source) else { return [] }
        guard !files.fileExists(atPath: destination.path) else {
            return ["\(source.path) wasn’t moved because protected storage already has an item with that name."]
        }
        do { try files.moveItem(at: source, to: destination); return [] } catch { return [error.localizedDescription] }
    }

    /// Replaces a folder with a link to `target`, moving its contents first.
    private static func link(_ link: URL, to target: URL) -> [String] {
        let files = FileManager.default
        if let destination = try? files.destinationOfSymbolicLink(atPath: link.path) {
            if destination == target.path { return [] }
            try? files.removeItem(at: link)
        }
        do {
            if files.fileExists(atPath: link.path) {
                if files.fileExists(atPath: target.path) {
                    var issues: [String] = []
                    for name in try files.contentsOfDirectory(atPath: link.path) {
                        issues += move(link.appending(path: name), to: target.appending(path: name))
                    }
                    guard issues.isEmpty else { return issues }
                    try files.removeItem(at: link)
                } else {
                    try files.moveItem(at: link, to: target)
                }
            }
            try files.createDirectory(at: target, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try files.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
            try files.createSymbolicLink(at: link, withDestinationURL: target)
            return []
        } catch { return [error.localizedDescription] }
    }

    private static func isLink(_ url: URL) -> Bool { (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil }

    /// Moves the built-in default store's data into `defaultStoreID`'s folder, which keeps everything,
    /// cookies included, under ~/Library/WebKit. Same files, other names, so sites keep their logins
    /// and storage. Then removes what is left of the default store, cookie file included.
    static func adoptDefaultStore(_ library: Library) throws {
        let files = FileManager.default
        let old = library.webKit.appending(path: "WebsiteData", directoryHint: .isDirectory)
        let oldCaches = library.caches.appending(path: "WebKit", directoryHint: .isDirectory)
        let cookies = library.httpStorages.appending(path: AppIdentity.bundleID + ".binarycookies")
        let store = defaultStoreFolder(library)
        if !files.fileExists(atPath: store.path), files.fileExists(atPath: old.path) || files.fileExists(atPath: cookies.path) {
            let building = store.deletingLastPathComponent().appending(path: ".default-store-moving", directoryHint: .isDirectory)
            try? files.removeItem(at: building)
            try files.createDirectory(at: building.appending(path: "Cookies"), withIntermediateDirectories: true)
            let names = ["LocalStorage", "IndexedDB", "DeviceIdHashSalts", "EnhancedSecurity", "MediaKeys", "MediaKeysHashSalts",
                         "ResourceLoadStatistics", "SearchHistory"]
            for name in names where files.fileExists(atPath: old.appending(path: name).path) {
                try files.moveItem(at: old.appending(path: name), to: building.appending(path: name))
            }
            // The default store names its per-origin folder "Default"; identifier stores call it "Origins".
            if files.fileExists(atPath: old.appending(path: "Default").path) {
                try files.moveItem(at: old.appending(path: "Default"), to: building.appending(path: "Origins"))
            }
            for name in ["CacheStorage", "HSTS", "AlternativeServices"] where files.fileExists(atPath: oldCaches.appending(path: name).path) {
                try files.moveItem(at: oldCaches.appending(path: name), to: building.appending(path: name))
            }
            if files.fileExists(atPath: cookies.path) {
                try files.moveItem(at: cookies, to: building.appending(path: "Cookies/Cookies.binarycookies"))
            }
            try files.moveItem(at: building, to: store)
        }
        guard files.fileExists(atPath: store.path) else { return }
        try? files.removeItem(at: old)
        try? files.removeItem(at: oldCaches)
        // The default store's cookie file and its leftovers from interrupted writes.
        for name in (try? files.contentsOfDirectory(atPath: library.httpStorages.path)) ?? []
        where name.hasPrefix(AppIdentity.bundleID + ".binarycookies") {
            try? files.removeItem(at: library.httpStorages.appending(path: name))
        }
    }

    /// WebKit keeps two things in the user's temporary folder, which other apps can read: blob contents
    /// (files a page builds or uploads while it's open) and AVFoundation's media cache. Neither can be
    /// moved, so Ikago removes them at launch and quit, when no page needs them. Never while another copy
    /// of Ikago is running (`isOnlyInstance`), whose pages may still hold them.
    static func removeTemporaryFiles(in temporary: URL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)) {
        let files = FileManager.default
        let networking = temporary.appending(path: "com.apple.WebKit.Networking+" + AppIdentity.bundleID, directoryHint: .isDirectory)
        for name in (try? files.contentsOfDirectory(atPath: networking.path)) ?? [] where name.hasPrefix("BlobRegistryFiles-") {
            try? files.removeItem(at: networking.appending(path: name))
        }
        try? files.removeItem(at: temporary.appending(path: AppIdentity.bundleID + "/WebKit/MediaCache"))
    }

    static var isOnlyInstance: Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: AppIdentity.bundleID).count <= 1
    }

    static func defaultStoreFolder(_ library: Library) -> URL {
        library.webKit.appending(path: "WebsiteDataStore/" + defaultStoreID.uuidString.lowercased(), directoryHint: .isDirectory)
    }
}
