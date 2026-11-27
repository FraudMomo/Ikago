import AppKit

struct DetectedBrowserProfile: Identifiable, Sendable, Equatable {
    let browser: String
    let name: String
    let directory: URL
    let kind: BrowserProfileImporter.Kind
    let cookieKey: ChromiumCookieCrypto.Browser?
    var preferred = false
    /// The browser's whole data folder (Chrome's `Google/Chrome`, `~/Library/Safari`): what the Allow picker opens, so one
    /// approval covers every profile and the list of profiles itself.
    var accessRoot: URL? = nil
    /// macOS hides this browser's data from Ikago until the person allows it, so its profiles aren't known yet.
    var needsAccess = false

    var id: String { directory.standardizedFileURL.path }
    var title: String { browser }
    var subtitle: String { needsAccess ? "Allow access to find your profiles" : name.isEmpty ? "Ready to import" : name }
}

/// Discovery reads profile metadata, never browsing records or cookies. macOS (14 and later) hides other apps' data
/// folders from Ikago until the person allows each one; a folder that exists but can't be listed shows as one
/// "allow access" entry for its browser rather than as a guessed, empty profile.
enum BrowserProfileDiscovery {
    private struct ChromiumSource {
        let browser: String
        let path: String
        let key: ChromiumCookieCrypto.Browser
        /// Opera keeps its profile in the data folder itself rather than in `Default`.
        var rootProfile = false
    }

    /// Bundle identifiers of every browser Ikago imports from; also used to show each browser's own icon.
    static let bundleIDs: [String: String] = [
        "Google Chrome": "com.google.Chrome", "Chrome Beta": "com.google.Chrome.beta",
        "Chrome Canary": "com.google.Chrome.canary", "Microsoft Edge": "com.microsoft.edgemac",
        "Brave": "com.brave.Browser", "Arc": "company.thebrowser.Browser", "Dia": "company.thebrowser.dia",
        "Vivaldi": "com.vivaldi.Vivaldi", "Chromium": "org.chromium.Chromium", "Opera": "com.operasoftware.Opera",
        "Opera GX": "com.operasoftware.OperaGX", "Comet": "ai.perplexity.comet",
        "Firefox": "org.mozilla.firefox", "Zen": "app.zen-browser.zen", "LibreWolf": "org.mozilla.librewolf",
        "Waterfox": "net.waterfox.waterfox", "Floorp": "one.ablaze.floorp",
        "Safari": "com.apple.Safari", "Safari Technology Preview": "com.apple.SafariTechnologyPreview"
    ]

    static func discover(home: URL, installedBrowsers: Set<String> = []) -> [DetectedBrowserProfile] {
        let support = home.appending(path: "Library/Application Support")
        let sources: [ChromiumSource] = [
            .init(browser: "Google Chrome", path: "Google/Chrome", key: .chrome),
            .init(browser: "Chrome Beta", path: "Google/Chrome Beta", key: .chrome),
            .init(browser: "Chrome Canary", path: "Google/Chrome Canary", key: .chrome),
            .init(browser: "Microsoft Edge", path: "Microsoft Edge", key: .edge),
            .init(browser: "Brave", path: "BraveSoftware/Brave-Browser", key: .brave),
            .init(browser: "Arc", path: "Arc/User Data", key: .arc),
            .init(browser: "Dia", path: "Dia/User Data", key: .dia),
            .init(browser: "Opera", path: "com.operasoftware.Opera", key: .opera, rootProfile: true),
            .init(browser: "Opera GX", path: "com.operasoftware.OperaGX", key: .opera, rootProfile: true),
            .init(browser: "Comet", path: "Comet", key: .comet),
            .init(browser: "Vivaldi", path: "Vivaldi", key: .vivaldi),
            .init(browser: "Chromium", path: "Chromium", key: .chromium)
        ]
        var found: [DetectedBrowserProfile] = []
        for source in sources {
            let root = support.appending(path: source.path)
            let hidden = isBlocked(root) || (installedBrowsers.contains(source.browser)
                && !FileManager.default.fileExists(atPath: root.path) && isBlocked(root.deletingLastPathComponent()))
            if hidden {
                found.append(.init(browser: source.browser, name: "", directory: root, kind: .chromium, cookieKey: source.key,
                                   preferred: true, accessRoot: root, needsAccess: true))
                continue
            }
            let localState = dictionary(root.appending(path: "Local State"))
            let profile = localState["profile"] as? [String: Any] ?? [:]
            let cache = profile["info_cache"] as? [String: [String: Any]] ?? [:]
            let recent = profile["last_used"] as? String ?? "Default"
            var folders = Set(cache.keys.filter(validFolder))
            for child in children(root) where child.lastPathComponent == "Default" || child.lastPathComponent.hasPrefix("Profile ") {
                folders.insert(child.lastPathComponent)
            }
            // A profile folder without data (a browser installed but never used) has nothing to import.
            if source.rootProfile { folders = hasProfileData(root, kind: .chromium) ? [""] : [] }
            for folder in folders.sorted() {
                let directory = folder.isEmpty ? root : root.appending(path: folder)
                let name = cache[folder]?["name"] as? String ?? (folder == "Default" || folder.isEmpty ? "Default profile" : folder)
                found.append(.init(browser: source.browser, name: String(name.prefix(128)), directory: directory,
                                   kind: .chromium, cookieKey: source.key, preferred: folder == recent || folder.isEmpty,
                                   accessRoot: root))
            }
        }
        for (browser, path) in [("Firefox", "Firefox"), ("Zen", "zen"), ("Zen", "Zen"),
                                ("LibreWolf", "librewolf"), ("Waterfox", "Waterfox"), ("Floorp", "Floorp")] {
            found += firefox(browser: browser, root: support.appending(path: path))
        }
        for (browser, folder) in [("Safari", "Safari"), ("Safari Technology Preview", "SafariTechnologyPreview")] {
            let safari = home.appending(path: "Library/\(folder)")
            if FileManager.default.fileExists(atPath: safari.path) {
                let hidden = isBlocked(safari)
                found.append(.init(browser: browser, name: "Bookmarks and history", directory: safari, kind: .safari, cookieKey: nil,
                                   preferred: true, accessRoot: safari, needsAccess: hidden))
            }
        }
        var seen = Set<String>()
        return found.filter { seen.insert($0.id).inserted }.sorted {
            if $0.browser != $1.browser { return $0.browser.localizedStandardCompare($1.browser) == .orderedAscending }
            if $0.preferred != $1.preferred { return $0.preferred }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// Installed apps remain selectable when macOS hides even their data folder's parent until access is allowed.
    @MainActor static func installedBrowsers() -> Set<String> {
        let chromium = ["Google Chrome", "Chrome Beta", "Chrome Canary", "Microsoft Edge", "Brave", "Arc", "Dia",
                        "Vivaldi", "Chromium", "Opera", "Opera GX", "Comet"]
        let apps = bundleIDs.filter { chromium.contains($0.key) }
        return Set(apps.compactMap { name, bundle in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) == nil ? nil : name
        })
    }

    private static func firefox(browser: String, root: URL) -> [DetectedBrowserProfile] {
        if isBlocked(root) {
            return [.init(browser: browser, name: "", directory: root, kind: .firefox, cookieKey: nil, preferred: true, accessRoot: root, needsAccess: true)]
        }
        let sections = ini(root.appending(path: "profiles.ini"))
        let installs = ini(root.appending(path: "installs.ini"))
        let defaults = Set((sections + installs).compactMap { section -> String? in
            guard section.name.hasPrefix("Install") || section.values["Locked"] != nil else { return nil }
            return section.values["Default"]
        })
        var profiles: [DetectedBrowserProfile] = []
        for section in sections where section.name.hasPrefix("Profile") {
            guard let path = section.values["Path"], !path.isEmpty else { continue }
            let directory = section.values["IsRelative"] == "0" ? URL(fileURLWithPath: path, isDirectory: true) : root.appending(path: path)
            guard hasProfileData(directory, kind: .firefox) else { continue }
            profiles.append(.init(browser: browser, name: String((section.values["Name"] ?? directory.lastPathComponent).prefix(128)),
                                  directory: directory, kind: .firefox, cookieKey: nil,
                                  preferred: defaults.isEmpty ? section.values["Default"] == "1" : defaults.contains(path), accessRoot: root))
        }
        // Include selectable profiles not listed individually in older profiles.ini files.
        for directory in children(root.appending(path: "Profiles")) where hasProfileData(directory, kind: .firefox) {
            if !profiles.contains(where: { $0.directory.standardizedFileURL == directory.standardizedFileURL }) {
                profiles.append(.init(browser: browser, name: directory.lastPathComponent, directory: directory,
                                      kind: .firefox, cookieKey: nil, preferred: directory.lastPathComponent.hasSuffix(".default-release"),
                                      accessRoot: root))
            }
        }
        return profiles
    }

    private static func hasProfileData(_ directory: URL, kind: BrowserProfileImporter.Kind) -> Bool {
        let names = kind == .chromium ? ["Bookmarks", "History", "Cookies", "Network/Cookies", "Sessions"]
            : ["places.sqlite", "cookies.sqlite", "sessionstore.jsonlz4", "sessionstore-backups"]
        return names.contains { FileManager.default.fileExists(atPath: directory.appending(path: $0).path) }
    }

    /// Whether the folder exists but macOS won't let Ikago list it (privacy protection, not absence).
    static func isBlocked(_ folder: URL) -> Bool {
        do { _ = try FileManager.default.contentsOfDirectory(atPath: folder.path); return false }
        catch { return ImportAccessError.isPermissionDenied(error) }
    }

    private static func validFolder(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\\")
    }

    private static func children(_ url: URL) -> [URL] {
        Array(((try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }.prefix(100))
    }

    private static func dictionary(_ file: URL) -> [String: Any] {
        guard ((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) <= 8_000_000,
              let data = try? Data(contentsOf: file) else { return [:] }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    private struct Section {
        var name: String
        var values: [String: String] = [:]
    }

    private static func ini(_ file: URL) -> [Section] {
        guard ((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) <= 1_000_000,
              let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        var result: [Section] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("[") && line.hasSuffix("]") {
                result.append(Section(name: String(line.dropFirst().dropLast())))
            } else if !line.hasPrefix("#"), !line.hasPrefix(";"), let equals = line.firstIndex(of: "="), !result.isEmpty {
                let key = line[..<equals].trimmingCharacters(in: .whitespaces)
                let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
                result[result.count - 1].values[key] = value
            }
        }
        return result
    }
}
