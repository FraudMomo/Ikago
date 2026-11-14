import AppKit

/// Light and dark icons. Two things differ by mode: which icon a site offers (`FaviconScript`), and how an SVG icon
/// with `@media (prefers-color-scheme: …)` rules draws. macOS's SVG renderer ignores those rules (it always draws
/// the light version), so the SVG's text is resolved for the mode before decoding. Stored bytes stay as the site
/// sent them; only decoded images and the page/site "last good icon" entries are kept per mode.
extension FaviconCache {
    /// Memory cache key: decoded images can differ by mode, the stored bytes don't.
    func memoryKey(_ key: String, dark: Bool) -> String { dark ? key + "|dark" : key }

    /// The page/site entry for one mode. Entries saved before modes existed have no suffix and are read as a fallback.
    static func modeKey(_ key: String, dark: Bool) -> String { key + (dark ? "|dark" : "|light") }

    /// Decodes icon bytes for a mode. Only SVGs that style themselves by color scheme decode differently.
    nonisolated static func decode(_ data: Data, dark: Bool) -> NSImage? {
        guard let text = String(data: data, encoding: .utf8), text.range(of: "prefers-color-scheme", options: .caseInsensitive) != nil,
              text.drop(while: { $0.isWhitespace || $0 == "\u{FEFF}" }).first == "<" else { return NSImage(data: data) }
        return NSImage(data: Data(resolvingColorScheme(text, dark: dark).utf8))
    }

    /// Unwraps the `@media (prefers-color-scheme: …)` blocks that match the mode and drops the rest.
    nonisolated static func resolvingColorScheme(_ text: String, dark: Bool) -> String {
        var output = ""
        var rest = text[...]
        while let media = rest.range(of: "@media", options: .caseInsensitive),
              let open = rest[media.upperBound...].firstIndex(of: "{") {
            let condition = rest[media.upperBound..<open].lowercased()
            output += rest[..<media.lowerBound]
            guard condition.contains("prefers-color-scheme") else {
                output += rest[media.lowerBound...open]
                rest = rest[rest.index(after: open)...]
                continue
            }
            // The block's matching brace; an unbalanced block leaves the rest as it is.
            var depth = 0, close: Substring.Index?
            var index = open
            while index < rest.endIndex {
                if rest[index] == "{" { depth += 1 } else if rest[index] == "}" { depth -= 1; if depth == 0 { close = index; break } }
                index = rest.index(after: index)
            }
            guard let close else { output += rest[media.lowerBound...]; return output }
            if condition.contains("dark") == dark { output += rest[rest.index(after: open)..<close] }
            rest = rest[rest.index(after: close)...]
        }
        return output + rest
    }
}
