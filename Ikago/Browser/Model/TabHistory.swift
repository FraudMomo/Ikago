import Foundation

/// A tab's Back history, kept with the session (and with recently closed tabs) so it survives relaunch, unloading and
/// ⌘⇧T, as in Chrome. WebKit's own `interactionState` restores everything (Back and Forward, scroll positions); every
/// engine also records the addresses behind the page, which is what a Chromium page (or a page that changed engine)
/// goes back through. Bounded: a few recent entries, and a WebKit state that fits in `maxState`.
struct TabHistory: Codable, Equatable {
    /// WebKit's `interactionState`, base64.
    var state: String? = nil
    /// The pages behind the current one, oldest first.
    var back: [String]? = nil
    /// The page this history leads up to. A page starting somewhere else (a tab that navigated to another address,
    /// or swapped its view for another engine or an extension's configuration) doesn't take it.
    var url: String? = nil

    static let maxBack = 12
    static let maxState = 32 * 1024

    /// Only web addresses, a few of the latest, each a sane length.
    static func trimmed(_ urls: [String]) -> [String]? {
        let kept = urls.filter { AddressResolver.isWebURL($0) && $0.utf8.count <= 2048 }.suffix(maxBack)
        return kept.isEmpty ? nil : Array(kept)
    }

    var isEmpty: Bool { state == nil && (back ?? []).isEmpty }

    /// Whether a page starting at `destination` should take this history.
    func leads(to destination: String) -> Bool { url == nil || url == destination }
}
