import Foundation
import Security

/// Strong passwords for new-password fields (sign-up and change-password forms), on either engine.
///
/// With no rules from the site: Apple's readable format, three groups of six letters and digits joined by hyphens, with
/// one uppercase letter and one digit (`abcdef-ghij2k-lmnoPq`, about 71 bits). A site that states its rules
/// (`passwordrules`, `minlength`, `maxlength`, `pattern`) gets a password that keeps them. Every character comes from
/// `SecRandomCopyBytes` with rejection sampling, so no character is likelier than another.
enum PasswordGenerator {
    /// What a field says about the passwords it accepts.
    struct Rules: Equatable, Sendable {
        var minLength: Int?
        var maxLength: Int?
        /// Character classes that must each appear at least once.
        var required: [Set<Character>] = []
        /// Characters allowed at all; nil means the default classes.
        var allowed: Set<Character>?
        var maxConsecutive: Int?
        /// The field's `pattern` attribute, checked on the whole password.
        var pattern: String?

        /// From the key script's report: `passwordrules`, `minLength`, `maxLength` and `pattern`.
        init(passwordRules: String = "", minLength: Int? = nil, maxLength: Int? = nil, pattern: String? = nil) {
            self.minLength = minLength.flatMap { $0 > 0 ? $0 : nil }
            self.maxLength = maxLength.flatMap { $0 > 0 ? $0 : nil }
            self.pattern = pattern?.isEmpty == false ? pattern : nil
            parse(passwordRules)
        }

        init(_ report: [String: Any]?) {
            self.init(passwordRules: report?["rules"] as? String ?? "", minLength: report?["minLength"] as? Int,
                      maxLength: report?["maxLength"] as? Int, pattern: report?["pattern"] as? String)
        }

        /// Apple's `passwordrules` syntax: `required: upper; required: digit; allowed: [-().&@?'#,/+]; minlength: 8;
        /// max-consecutive: 2`. Unknown parts are ignored.
        private mutating func parse(_ text: String) {
            for rule in text.split(separator: ";") {
                let parts = rule.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                guard parts.count == 2 else { continue }
                let value = parts[1]
                switch parts[0] {
                case "minlength": if let number = Int(value), number > 0 { minLength = max(minLength ?? 0, number) }
                case "maxlength": if let number = Int(value), number > 0 { maxLength = min(maxLength ?? .max, number) }
                case "max-consecutive": if let number = Int(value), number > 0 { maxConsecutive = number }
                case "required":
                    let set = Self.classes(value)
                    if !set.isEmpty { required.append(set) }
                case "allowed":
                    let set = Self.classes(value)
                    if !set.isEmpty { allowed = (allowed ?? []).union(set) }
                default: break
                }
            }
        }

        /// A comma-separated list of named classes and bracketed characters, as one set.
        private static func classes(_ value: String) -> Set<Character> {
            var result = Set<Character>()
            var rest = Substring(value)
            while !rest.isEmpty {
                rest = rest.drop { $0 == "," || $0 == " " }
                if rest.first == "[" {
                    guard let close = rest.dropFirst().firstIndex(of: "]") else { break }
                    result.formUnion(rest[rest.index(after: rest.startIndex)..<close].filter { $0.isASCII && !$0.isWhitespace })
                    rest = rest[rest.index(after: close)...]
                } else {
                    let name = rest.prefix { $0 != "," }
                    rest = rest.dropFirst(name.count)
                    switch name.trimmingCharacters(in: .whitespaces) {
                    case "upper": result.formUnion(PasswordGenerator.upper)
                    case "lower": result.formUnion(PasswordGenerator.lower)
                    case "digit": result.formUnion(PasswordGenerator.digits)
                    case "special": result.formUnion(PasswordGenerator.special)
                    case "ascii-printable", "unicode": result.formUnion(PasswordGenerator.upper + PasswordGenerator.lower
                                                                         + PasswordGenerator.digits + PasswordGenerator.special)
                    default: break
                    }
                }
            }
            return result
        }

        var isDefault: Bool {
            required.isEmpty && allowed == nil && maxConsecutive == nil && pattern == nil
                && (minLength ?? 0) <= 20 && (maxLength ?? .max) >= 20
        }
    }

    // Letters and digits that can't be confused with each other (no l, I, O, 0, 1), as Apple's are.
    static let lower = Array("abcdefghijkmnopqrstuvwxyz")
    static let upper = Array("ABCDEFGHJKLMNPQRSTUVWXYZ")
    static let digits = Array("23456789")
    static let special = Array("-~!@#$%^&*_+=`|(){}[:;\"'<>,.?]/")

    /// A password for a field with `rules`, or nil when the rules can't be met (they contradict each other).
    static func generate(_ rules: Rules = Rules()) -> String? {
        for _ in 0..<50 {
            let candidate = rules.isDefault ? readable() : custom(rules)
            guard let candidate else { return nil }
            if satisfies(candidate, rules) { return candidate }
        }
        return nil
    }

    /// Three groups of six, hyphenated: one uppercase letter and one digit at random places, the rest lowercase.
    private static func readable() -> String {
        var characters = (0..<18).map { _ in lower[random(lower.count)] }
        let upperAt = random(18)
        var digitAt = random(17)
        if digitAt >= upperAt { digitAt += 1 }
        characters[upperAt] = upper[random(upper.count)]
        characters[digitAt] = digits[random(digits.count)]
        return [characters[0..<6], characters[6..<12], characters[12..<18]].map { String($0) }.joined(separator: "-")
    }

    /// From the site's allowed characters, with each required class once at a random place.
    private static func custom(_ rules: Rules) -> String? {
        let allowed = rules.allowed ?? Set(lower + upper + digits)
        let pool = Array(allowed.union(rules.required.reduce(into: Set<Character>()) { $0.formUnion($1) })).sorted()
        guard !pool.isEmpty else { return nil }
        let lowest = max(rules.minLength ?? 0, rules.required.count, 1)
        let highest = rules.maxLength ?? .max
        guard lowest <= highest else { return nil }
        let length = min(max(20, lowest), highest)
        var characters = (0..<length).map { _ in pool[random(pool.count)] }
        var places = Array(0..<length)
        for set in rules.required where !characters.contains(where: set.contains) {
            guard !places.isEmpty else { return nil }
            let place = places.remove(at: random(places.count))
            let choices = Array(set).sorted()
            characters[place] = choices[random(choices.count)]
        }
        return String(characters)
    }

    static func satisfies(_ password: String, _ rules: Rules) -> Bool {
        if let minimum = rules.minLength, password.count < minimum { return false }
        if let maximum = rules.maxLength, password.count > maximum { return false }
        if let allowed = rules.allowed, !password.allSatisfy({ character in
            allowed.contains(character) || rules.required.contains { $0.contains(character) } }) {
            return false
        }
        if !rules.required.allSatisfy({ set in password.contains(where: set.contains) }) { return false }
        if let limit = rules.maxConsecutive {
            var run = 1
            for (previous, next) in zip(password, password.dropFirst()) {
                run = previous == next ? run + 1 : 1
                if run > limit { return false }
            }
        }
        if let pattern = rules.pattern {
            guard let expression = try? NSRegularExpression(pattern: "^(?:" + pattern + ")$") else { return true }
            let range = NSRange(password.startIndex..., in: password)
            if expression.firstMatch(in: password, range: range) == nil { return false }
        }
        return true
    }

    /// A uniformly random integer in `0..<upper` from the system's secure generator.
    static func random(_ upper: Int) -> Int {
        precondition(upper > 0 && upper <= 256)
        let limit = 256 - 256 % upper
        while true {
            var byte: UInt8 = 0
            guard SecRandomCopyBytes(kSecRandomDefault, 1, &byte) == errSecSuccess else { continue }
            if Int(byte) < limit { return Int(byte) % upper }
        }
    }
}
