import SwiftUI

/// Match emphasis: search suggestions bold what the user has *not* typed; titles and
/// addresses bold the word prefixes that matched.
enum OmniboxHighlight {
    static func search(_ text: String, typed: String) -> AttributedString {
        var result = AttributedString(text)
        let needle = typed.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty, text.lowercased().hasPrefix(needle.lowercased()), text.count > needle.count,
              let start = result.index(result.startIndex, offsetByCharacters: needle.count, in: result) else { return result }
        result[start..<result.endIndex].font = .system(size: 13, weight: .semibold)
        return result
    }

    static func matched(_ text: String, terms: [String]) -> AttributedString {
        var result = AttributedString(text)
        let lower = Array(text.lowercased())
        guard !terms.isEmpty, lower.count == text.count else { return result }
        for term in terms where !term.isEmpty {
            let needle = Array(term)
            guard needle.count <= lower.count else { continue }
            for offset in 0...(lower.count - needle.count) {
                let atWordStart = offset == 0 || !(lower[offset - 1].isLetter || lower[offset - 1].isNumber)
                guard atWordStart, Array(lower[offset..<offset + needle.count]) == needle,
                      let start = result.index(result.startIndex, offsetByCharacters: offset, in: result),
                      let end = result.index(start, offsetByCharacters: needle.count, in: result) else { continue }
                result[start..<end].font = .system(size: 13, weight: .semibold)
            }
        }
        return result
    }
}

private extension AttributedString {
    func index(_ from: AttributedString.Index, offsetByCharacters count: Int, in string: AttributedString) -> AttributedString.Index? {
        var index = from
        for _ in 0..<count {
            guard index < string.endIndex else { return nil }
            index = string.characters.index(after: index)
        }
        return index
    }
}
