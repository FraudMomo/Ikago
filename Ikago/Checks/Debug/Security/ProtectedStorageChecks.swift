#if DEBUG
import Foundation

/// Moving into protected storage, on a disposable home folder and container. Never touches real data.
@MainActor
enum ProtectedStorageChecks {
    static func run(check: (Bool, String) -> Void) {
        let files = FileManager.default
        let base = files.temporaryDirectory.appending(path: "ikago-protected-\(UUID().uuidString)")
        defer { try? files.removeItem(at: base) }
        let home = base.appending(path: "home"), container = base.appending(path: "container")
        let library = ProtectedStorage.Library(home: home)
        func put(_ url: URL, _ text: String = "x") {
            try? files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data(text.utf8).write(to: url)
        }
        func read(_ url: URL) -> String? { (try? Data(contentsOf: url)).map { String(decoding: $0, as: UTF8.self) } }
        put(library.support.appending(path: "session.json"), "session")
        put(library.support.appending(path: "Chromium/profile/Cookies"))
        put(library.support.appending(path: "Updates/status.json"))
        put(library.support.appending(path: ".migrated-from-earlier-identity"))
        put(library.webKit.appending(path: "WebsiteData/LocalStorage/origin"), "local")
        put(library.webKit.appending(path: "WebsiteData/Default/salt"), "salt")
        put(library.webKit.appending(path: "WebsiteData/ResourceMonitorThrottler/db"))
        put(library.webKit.appending(path: "WebsiteDataStore/0d2c4b0e-0000-4000-8000-000000000001/Cookies/Cookies.binarycookies"), "space")
        put(library.caches.appending(path: "WebKit/HSTS/HSTS.plist"), "hsts")
        put(library.caches.appending(path: "WebKit/NetworkCache/record"))
        put(library.httpStorages.appending(path: AppIdentity.bundleID + ".binarycookies"), "cookies")
        put(library.httpStorages.appending(path: AppIdentity.bundleID + ".binarycookies_tmp_1.dat"))
        put(library.httpStorages.appending(path: "other.app.binarycookies"), "other")
        put(library.chromiumCache.appending(path: "Chromium/cache"))

        let issues = ProtectedStorage.migrate(library, into: container)
        check(issues.isEmpty, "moving into protected storage reports no problems \(issues)")
        let data = container.appending(path: "Ikago")
        check(read(data.appending(path: "session.json")) == "session" && !files.fileExists(atPath: library.support.appending(path: "session.json").path),
              "the session moves into protected storage and leaves no copy")
        check(files.fileExists(atPath: data.appending(path: "Chromium/profile/Cookies").path), "Chromium profiles move into protected storage")
        check(files.fileExists(atPath: library.support.appending(path: "Updates/status.json").path), "the updater's folder stays reachable")
        check((try? files.destinationOfSymbolicLink(atPath: library.webKit.path)) == container.appending(path: "WebKit").path,
              "WebKit's folder links into protected storage")
        let store = ProtectedStorage.defaultStoreFolder(library)
        check(read(store.appending(path: "LocalStorage/origin")) == "local" && read(store.appending(path: "Origins/salt")) == "salt"
              && read(store.appending(path: "HSTS/HSTS.plist")) == "hsts", "the default store's site data moves with it")
        check(read(store.appending(path: "Cookies/Cookies.binarycookies")) == "cookies", "the default store's cookies move into protected storage")
        check(read(container.appending(path: "WebKit/WebsiteDataStore/0d2c4b0e-0000-4000-8000-000000000001/Cookies/Cookies.binarycookies")) == "space",
              "isolated Spaces keep their stores")
        check(!files.fileExists(atPath: library.httpStorages.appending(path: AppIdentity.bundleID + ".binarycookies").path)
              && !files.fileExists(atPath: library.httpStorages.appending(path: AppIdentity.bundleID + ".binarycookies_tmp_1.dat").path),
              "no cookie file is left in the shared HTTPStorages folder")
        check(read(library.httpStorages.appending(path: "other.app.binarycookies")) == "other", "other apps' files are left alone")
        check(!files.fileExists(atPath: library.chromiumCache.path), "Chromium's old cache folder is removed")
        check(!files.fileExists(atPath: container.appending(path: "WebKit/WebsiteData").path), "nothing is left of the old default store")
        check(ProtectedStorage.migrate(library, into: container).isEmpty, "moving again changes nothing")

        // A name in both places is reported and kept, never overwritten.
        put(library.support.appending(path: "session.json"), "newer")
        let conflict = ProtectedStorage.migrate(library, into: container)
        check(!conflict.isEmpty && read(data.appending(path: "session.json")) == "session"
              && read(library.support.appending(path: "session.json")) == "newer", "a conflict is reported and nothing is overwritten")

        // WebKit's blob files and media cache in the temporary folder go; everything else stays.
        let temporary = base.appending(path: "T")
        let networking = temporary.appending(path: "com.apple.WebKit.Networking+" + AppIdentity.bundleID)
        put(networking.appending(path: "BlobRegistryFiles-AbCd1234/blob"), "upload")
        put(networking.appending(path: "Other/keep"))
        put(temporary.appending(path: AppIdentity.bundleID + "/WebKit/MediaCache/chunk"), "video")
        put(temporary.appending(path: "com.apple.WebKit.Networking+other.app/BlobRegistryFiles-x/blob"))
        ProtectedStorage.removeTemporaryFiles(in: temporary)
        check(!files.fileExists(atPath: networking.appending(path: "BlobRegistryFiles-AbCd1234").path)
              && !files.fileExists(atPath: temporary.appending(path: AppIdentity.bundleID + "/WebKit/MediaCache").path),
              "WebKit's blob files and media cache are removed from the temporary folder")
        check(files.fileExists(atPath: networking.appending(path: "Other/keep").path)
              && files.fileExists(atPath: temporary.appending(path: "com.apple.WebKit.Networking+other.app/BlobRegistryFiles-x/blob").path),
              "other temporary files and other apps' files stay")
    }
}
#endif
