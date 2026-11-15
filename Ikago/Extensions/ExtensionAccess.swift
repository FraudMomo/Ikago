import Foundation
import Observation
import WebKit

/// Which websites each extension may read and change: an extension runs on every website, or asks on each
/// one, where the person chooses Always Allow, Allow for One Day or Don't Allow. One store for both engines, keyed by the
/// extension (a Web Store extension has the same key on both). Extensions installed before this existed keep running
/// everywhere; new ones start asking (`startAsking`). Each engine applies the choices (`ExtensionManager+Access`,
/// `ChromiumExtensions+Access`), and the first-visit card asks (`ExtensionAccessPresenter`).
@MainActor @Observable
final class ExtensionAccess {
    static let shared = ExtensionAccess()

    enum Grant: Codable, Equatable { case always, never, until(Date) }

    struct Entry: Codable, Equatable {
        var everySite = true
        /// Registrable domain → the choice there; it covers the site's subdomains.
        var sites: [String: Grant] = [:]
    }

    /// What applies on one website.
    enum Status: Equatable { case everySite, always, oneDay(Date), never, ask }

    /// The choices offered for a website.
    enum Choice: CaseIterable { case always, oneDay, never, everySite }

    private(set) var entries: [String: Entry] = [:]
    /// Engines re-apply an extension's access when it changes.
    @ObservationIgnored var onChange: [(String) -> Void] = []
    @ObservationIgnored private var expiry: Timer?

    private static var file: URL {
        (WebProfiles.isTestMode ? SessionStore.testDirectory : AppIdentity.dataDirectory).appending(path: "Extension Access.json")
    }

    init() {
        if let data = try? Data(contentsOf: Self.file), let saved = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = saved
        }
        scheduleExpiry()
    }

    /// The website an address belongs to, for choices (web pages only).
    nonisolated static func site(_ url: URL?) -> String? {
        guard let url, ["http", "https"].contains(url.scheme?.lowercased() ?? ""), let host = url.host?.lowercased(), !host.isEmpty else { return nil }
        return PublicSuffix.registrableDomain(host)
    }

    /// The match pattern for a website and its subdomains (an address or a one-word host has none).
    nonisolated static func pattern(for site: String) -> String {
        let plain = !site.contains(".") || site.allSatisfy { $0.isNumber || $0 == "." } || site.contains(":")
        return plain ? "*://\(site)/*" : "*://*.\(site)/*"
    }

    func entry(_ key: String) -> Entry { entries[key] ?? Entry() }

    func status(_ key: String, site: String) -> Status {
        let entry = entry(key)
        switch entry.sites[site] {
        case .always: return .always
        case .never: return .never
        case .until(let date) where date > .now: return .oneDay(date)
        default: return entry.everySite ? .everySite : .ask
        }
    }

    /// The websites with an allowance in force, and until when (nil: always).
    func allowedSites(_ key: String) -> [String: Date?] {
        var sites: [String: Date?] = [:]
        for (site, grant) in entry(key).sites {
            switch grant {
            case .always: sites[site] = .some(nil)
            case .until(let date) where date > .now: sites[site] = date
            default: break
            }
        }
        return sites
    }

    func choose(_ choice: Choice, key: String, site: String) {
        var entry = entry(key)
        switch choice {
        case .everySite:
            entry.everySite = true
            entry.sites[site] = nil
        case .always, .oneDay, .never:
            // A choice for one website means the extension now asks everywhere else.
            entry.everySite = false
            entry.sites[site] = choice == .always ? .always : choice == .never ? .never : .until(.now.addingTimeInterval(86_400))
        }
        save(key, entry)
    }

    func setEverySite(_ on: Bool, key: String) {
        var entry = entry(key)
        entry.everySite = on
        save(key, entry)
    }

    func forget(site: String, key: String) {
        var entry = entry(key)
        entry.sites[site] = nil
        save(key, entry)
    }

    /// A newly installed extension asks on each website before it runs there.
    func startAsking(_ key: String) {
        guard entries[key] == nil else { return }
        save(key, Entry(everySite: false))
    }

    func removed(_ key: String) {
        guard entries.removeValue(forKey: key) != nil else { return }
        write()
    }

    /// Whether an extension asks for this address: one of its patterns (sites it reads, or its content scripts) matches.
    static func wants(_ patterns: [String], _ url: URL) -> Bool {
        patterns.contains { (try? WKWebExtension.MatchPattern(string: $0))?.matches(url) == true }
    }

    // MARK: Saving

    private func save(_ key: String, _ entry: Entry) {
        entries[key] = entry
        write()
        onChange.forEach { $0(key) }
        scheduleExpiry()
    }

    private func write() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? FileManager.default.createDirectory(at: Self.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: Self.file, options: .atomic)
    }

    /// A one-day allowance ends on its own: the engines are told again when the next one runs out.
    private func scheduleExpiry() {
        expiry?.invalidate()
        let ends = entries.flatMap { key, entry in entry.sites.values.compactMap { grant -> (String, Date)? in
            if case .until(let date) = grant, date > .now { return (key, date) } else { return nil }
        } }
        guard let next = ends.min(by: { $0.1 < $1.1 }) else { return }
        let timer = Timer(fire: next.1.addingTimeInterval(1), interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                for (key, date) in ends where date <= .now.addingTimeInterval(2) { self.onChange.forEach { $0(key) } }
                self.scheduleExpiry()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        expiry = timer
    }
}
