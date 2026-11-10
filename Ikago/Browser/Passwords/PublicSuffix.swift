import Foundation

/// The registrable domain ("eTLD+1") of a host, from Mozilla's Public Suffix List bundled in Resources
/// (`public_suffix_list.dat`, MPL 2.0). "mail.google.com" → "google.com", "alice.github.io" → itself,
/// because github.io is a public suffix and its subdomains belong to different people.
enum PublicSuffix {
    private struct Rules: Sendable {
        var exact: Set<String> = [], wildcard: Set<String> = [], exception: Set<String> = []
    }

    private static let rules: Rules = {
        guard let url = Bundle.main.url(forResource: "public_suffix_list", withExtension: "dat"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return Rules() }
        return parse(text)
    }()

    private static func parse(_ text: String) -> Rules {
        var rules = Rules()
        for line in text.split(whereSeparator: \.isNewline) {
            let rule = line.split(whereSeparator: \.isWhitespace).first.map(String.init)?.lowercased() ?? ""
            guard !rule.isEmpty, !rule.hasPrefix("//") else { continue }
            if rule.hasPrefix("!") { rules.exception.insert(String(rule.dropFirst())) }
            else if rule.hasPrefix("*.") { rules.wildcard.insert(String(rule.dropFirst(2))) }
            else { rules.exact.insert(rule) }
        }
        return rules
    }

    /// Parses the list off the main thread at launch, so the first page that needs it doesn't wait.
    static func warm() {
        Task.detached(priority: .utility) { _ = rules.exact.isEmpty }
    }

    /// Whether the list loaded; without it every host stands alone (`registrableDomain` returns the host).
    static var isAvailable: Bool { !rules.exact.isEmpty }

    /// The registrable domain of a lowercased host, or the host itself for IP addresses, single labels,
    /// public suffixes and when the list is missing.
    static func registrableDomain(_ host: String) -> String {
        let host = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let labels = host.split(separator: ".").map(String.init)
        guard labels.count > 1, isAvailable, !host.contains(":"),
              !labels.allSatisfy({ $0.allSatisfy(\.isNumber) }) else { return host }
        // The longest matching rule wins; an exception rule makes its own parent the suffix.
        var suffixLength = 1  // the implicit "*" rule
        for start in 0..<labels.count {
            let candidate = labels[start...].joined(separator: ".")
            let length = labels.count - start
            if rules.exception.contains(candidate) { suffixLength = length - 1; break }
            let parent = labels[(start + 1)...].joined(separator: ".")
            if rules.exact.contains(candidate) || (start + 1 < labels.count && rules.wildcard.contains(parent)) {
                suffixLength = max(suffixLength, length)
            }
        }
        guard suffixLength < labels.count else { return host }  // the host is itself a public suffix
        return labels[(labels.count - suffixLength - 1)...].joined(separator: ".")
    }
}
