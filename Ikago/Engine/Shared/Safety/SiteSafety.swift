import Foundation

/// Warns before opening a page that imitates another site or is on a public phishing list. Everything
/// is decided on this Mac: no address is ever sent anywhere. Warnings can always be overridden, so a
/// wrong guess or a bad list entry costs one click. This is not a guarantee: new phishing sites that
/// imitate nothing Ikago knows, and aren't listed yet, get no warning.
@MainActor
enum SiteSafety {
    struct Warning: Equatable {
        let message: String
        /// The genuine site this one imitates, when known.
        let imitates: String?
    }

    private static var knownCache: (state: ObjectIdentifier?, generation: Int, domains: Set<String>) = (nil, -1, [])

    static func warning(for url: URL, state: BrowserState?) -> Warning? {
        guard let state, state.browserPreferences.fraudulentWebsiteWarning ?? true,
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host?.lowercased(), !isExempt(host, state: state) else { return nil }
        if let imitated = SiteSafetyRules.imitatedSite(host: host, known: knownDomains(state)) {
            return Warning(message: "This address looks like \(imitated.domain), but it isn’t. \(imitated.reason)", imitates: imitated.domain)
        }
        if ThreatHosts.shared.contains(host) {
            return Warning(message: "This site is on a public list of reported phishing sites. It may try to steal passwords or payment details.", imitates: nil)
        }
        return nil
    }

    /// Continue Anyway: remembered for normal windows, and for the window's lifetime in private ones.
    static func allow(_ host: String, state: BrowserState?) {
        guard let state else { return }
        var sites = state.browserPreferences.siteSafetyExceptions ?? []
        if !sites.contains(host.lowercased()) { sites.append(host.lowercased()) }
        state.browserPreferences.siteSafetyExceptions = sites
    }

    private static func isExempt(_ host: String, state: BrowserState) -> Bool {
        BrowserPreferences.isLoopback(host) || !host.contains(".") || (state.browserPreferences.siteSafetyExceptions ?? []).contains(host)
    }

    /// Sites you actually use are worth protecting too: bookmarks, and pages you typed or often visit.
    private static func knownDomains(_ state: BrowserState) -> Set<String> {
        let owner = ObjectIdentifier(state), generation = state.knownSitesGeneration
        if knownCache.state == owner, knownCache.generation == generation { return knownCache.domains }
        var hosts = state.bookmarks.map(\.url)
        hosts += state.history.filter { ($0.typed ?? 0) > 0 || ($0.visits ?? 0) >= 3 }.map(\.url)
        let domains = Set(hosts.compactMap { URLComponents(string: $0)?.host?.lowercased() }.map(SiteSafetyRules.registrable))
        knownCache = (owner, generation, domains)
        return domains
    }
}

/// The rules themselves, free of browser state.
enum SiteSafetyRules {
    struct Imitation: Equatable { let domain: String; let reason: String }

    /// Sites phishing most often imitates: large services, banks, payments and shops.
    static let protected: Set<String> = [
        "google.com", "gmail.com", "youtube.com", "apple.com", "icloud.com", "microsoft.com", "microsoftonline.com",
        "live.com", "outlook.com", "office.com", "github.com", "gitlab.com", "paypal.com", "amazon.com", "facebook.com",
        "instagram.com", "whatsapp.com", "twitter.com", "linkedin.com", "netflix.com", "spotify.com", "dropbox.com",
        "adobe.com", "steamcommunity.com", "steampowered.com", "discord.com", "telegram.org", "coinbase.com", "binance.com",
        "metamask.io", "kraken.com", "chase.com", "wellsfargo.com", "bankofamerica.com", "citibank.com",
        "americanexpress.com", "mastercard.com", "stripe.com", "shopify.com", "ebay.com", "walmart.com", "fedex.com",
        "klarna.com", "revolut.com", "anthropic.com", "claude.ai", "openai.com", "chatgpt.com", "proton.me", "yahoo.com",
        "samsung.com", "cloudflare.com", "wikipedia.org", "reddit.com", "tiktok.com", "duckduckgo.com",
    ]
    /// Suffixes under which anyone can register; a name under them belongs to its own owner.
    private static let sharedSuffixes: Set<String> = [
        "co.uk", "org.uk", "ac.uk", "gov.uk", "com.au", "net.au", "org.au", "co.jp", "co.nz", "co.in", "co.kr", "com.br", "com.cn",
        "com.mx", "com.tr", "co.za", "com.sg", "com.hk", "vercel.app", "github.io", "pages.dev", "netlify.app", "web.app",
        "firebaseapp.com", "herokuapp.com", "cloudfront.net", "workers.dev", "appspot.com", "azurewebsites.net", "s3.amazonaws.com",
    ]
    private static let phishingWords: Set<String> = ["login", "signin", "secure", "verify", "account", "support", "update", "wallet", "auth", "billing", "unlock", "recover"]
    /// Top-level domains so cheap or abused that a famous name on one is rarely genuine.
    private static let abusedTLDs: Set<String> = ["tk", "ml", "ga", "cf", "gq", "top", "xyz", "icu", "buzz", "click", "rest", "cyou", "sbs", "lol"]

    static func registrable(_ host: String) -> String {
        let labels = host.split(separator: ".").map(String.init)
        guard labels.count > 2 else { return host }
        if labels.count >= 3, sharedSuffixes.contains(labels.suffix(2).joined(separator: ".")) { return labels.suffix(3).joined(separator: ".") }
        if labels.count >= 4, sharedSuffixes.contains(labels.suffix(3).joined(separator: ".")) { return labels.suffix(4).joined(separator: ".") }
        return labels.suffix(2).joined(separator: ".")
    }

    /// Each protected site by its name ("paypal" → "paypal.com").
    private static let brands = Dictionary(protected.map { (String($0.split(separator: ".").first ?? ""), $0) }, uniquingKeysWith: { first, _ in first })

    static func imitatedSite(host: String, known: Set<String>) -> Imitation? {
        guard !isIPAddress(host) else { return nil }
        let domain = registrable(host)
        if protected.contains(domain) || known.contains(domain) { return nil }
        let name = String(domain.split(separator: ".").first ?? "")
        guard !name.isEmpty else { return nil }
        let tld = String(domain.split(separator: ".").last ?? "")
        let targets = brands.merging(known.map { (String($0.split(separator: ".").first ?? ""), $0) }) { first, _ in first }

        // Punycode: аррӏе.com in Cyrillic, or mixed alphabets inside one name.
        if name.hasPrefix("xn--"), let decoded = Punycode.decode(String(name.dropFirst(4))) {
            if let target = targets[skeleton(decoded)] {
                return Imitation(domain: target, reason: "It uses characters from another alphabet that look like the real ones.")
            }
            if hasMixedScripts(decoded) {
                return Imitation(domain: domain, reason: "It mixes characters from different alphabets, a common way to disguise an address.")
            }
        }
        // paypal.com.secure-login.net, or www-paypal.com.
        for target in protected {
            let embedded = target.replacingOccurrences(of: ".", with: "-")
            let front = host.hasSuffix(domain) ? String(host.dropLast(domain.count)) : host
            if ("." + front).contains("." + target + ".") || name.contains(embedded) {
                return Imitation(domain: target, reason: "The real site’s name is only part of a longer address owned by someone else.")
            }
        }
        if name.hasPrefix("www-"), let target = brands[String(name.dropFirst(4))] {
            return Imitation(domain: target, reason: "The real site’s name is only part of a longer address owned by someone else.")
        }
        // paypal-login.com.
        let parts = name.split(separator: "-").map(String.init)
        if parts.count > 1, let brand = parts.first(where: { $0.count >= 5 && brands[$0] != nil }), parts.contains(where: phishingWords.contains) {
            return Imitation(domain: brands[brand]!, reason: "Sites often add words like “login” to a famous name to look official.")
        }
        // paypal.tk: the exact name, on a domain ending commonly used for abuse.
        if let target = brands[name], abusedTLDs.contains(tld) {
            return Imitation(domain: target, reason: "The real site doesn’t use this domain ending.")
        }
        if brands[name] != nil || targets[name] != nil { return nil }  // google.se and the like
        // paypa1.com, rnicrosoft.com.
        if skeleton(name) != name, let target = targets[skeleton(name)] {
            return Imitation(domain: target, reason: "Some characters have been swapped for similar-looking ones.")
        }
        // gooogle.com, amazom.com.
        if name.count >= 6, let target = targets.first(where: { $0.key.count >= 6 && abs($0.key.count - name.count) <= 1 && editDistance($0.key, name) == 1 })?.value {
            return Imitation(domain: target, reason: "It differs by a single character, a common typing trap.")
        }
        return nil
    }

    private static func isIPAddress(_ host: String) -> Bool {
        host.contains(":") || host.allSatisfy { $0.isNumber || $0 == "." }
    }

    /// Folds characters that look alike, so disguised names compare equal to the real ones.
    static func skeleton(_ text: String) -> String {
        let similar: [Character: Character] = [
            "0": "o", "1": "l", "а": "a", "е": "e", "о": "o", "р": "p", "с": "c", "у": "y", "х": "x", "і": "i", "ј": "j", "һ": "h",
            "ԁ": "d", "ѕ": "s", "ӏ": "l", "ո": "n", "ɡ": "g", "α": "a", "ο": "o", "ν": "v", "ı": "i",
        ]
        return String(text.lowercased().map { similar[$0] ?? $0 })
            .replacingOccurrences(of: "rn", with: "m")
            .replacingOccurrences(of: "vv", with: "w")
    }

    /// Latin mixed with Cyrillic or Greek. Latin with ä, å or ö on its own is ordinary.
    static func hasMixedScripts(_ text: String) -> Bool {
        var latin = false, other = false
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x61...0x7A, 0xC0...0x24F: latin = true
            case 0x370...0x52F: other = true
            default: break
            }
        }
        return latin && other
    }

    /// Damerau-Levenshtein: one insertion, deletion, substitution or swap counts as 1.
    static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        var table = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { table[i][0] = i }
        for j in 0...b.count { table[0][j] = j }
        guard !a.isEmpty, !b.isEmpty else { return max(a.count, b.count) }
        for i in 1...a.count {
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                table[i][j] = min(table[i - 1][j] + 1, table[i][j - 1] + 1, table[i - 1][j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] { table[i][j] = min(table[i][j], table[i - 2][j - 2] + 1) }
            }
        }
        return table[a.count][b.count]
    }
}

/// RFC 3492 decoding, for the part of a label after "xn--".
enum Punycode {
    static func decode(_ input: String) -> String? {
        var output: [UInt32] = [], rest = Substring(input)
        if let dash = input.lastIndex(of: "-") {
            guard input[..<dash].allSatisfy(\.isASCII) else { return nil }
            output = input[..<dash].unicodeScalars.map(\.value)
            rest = input[input.index(after: dash)...]
        }
        var n: UInt32 = 128, i: UInt32 = 0, bias: UInt32 = 72
        var digits = rest.unicodeScalars.makeIterator()
        var next = digits.next()
        while next != nil {
            let start = i
            var weight: UInt32 = 1, k: UInt32 = 36
            while true {
                guard let scalar = next else { return nil }
                next = digits.next()
                let digit: UInt32
                switch scalar.value {
                case 0x61...0x7A: digit = scalar.value - 0x61
                case 0x41...0x5A: digit = scalar.value - 0x41
                case 0x30...0x39: digit = scalar.value - 0x30 + 26
                default: return nil
                }
                let (scaled, overflow) = digit.multipliedReportingOverflow(by: weight)
                guard !overflow, i <= UInt32.max - scaled else { return nil }
                i += scaled
                let threshold = k <= bias ? 1 : k >= bias + 26 ? 26 : k - bias
                if digit < threshold { break }
                let (product, weightOverflow) = weight.multipliedReportingOverflow(by: 36 - threshold)
                guard !weightOverflow else { return nil }
                weight = product
                k += 36
            }
            let count = UInt32(output.count) + 1
            var delta = (i - start) / (start == 0 ? 700 : 2)
            delta += delta / count
            var steps: UInt32 = 0
            while delta > 455 { delta /= 35; steps += 36 }
            bias = steps + 36 * delta / (delta + 38)
            n += i / count
            i %= count
            guard n <= 0x10FFFF else { return nil }
            output.insert(n, at: Int(i))
            i += 1
        }
        var text = ""
        for value in output {
            guard let scalar = Unicode.Scalar(value) else { return nil }
            text.unicodeScalars.append(scalar)
        }
        return text
    }
}
