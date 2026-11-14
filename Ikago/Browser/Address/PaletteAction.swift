import AppKit

/// Browser commands and settings the address field finds by name, like Spotlight's actions: "private" offers New
/// Private Window, "dark" Dark Mode, "split" the split view commands, "tab counts" the setting in Settings. They rank
/// below what-you-typed and earlier searches, so Return still searches; ↓ or a click runs one. Each runs a window
/// action through the responder chain (the same one its menu item or shortcut uses), with an optional argument.
/// The catalogue is `PaletteAction.builtIn` (PaletteActionCatalog.swift) plus every setting (`settings`, filled by the UI).
struct PaletteAction: Equatable {
    enum Kind: Equatable { case command, setting }

    let id: String
    let title: String
    let symbol: String
    /// The keyboard shortcut that does the same, if any.
    let shortcut: String
    let keywords: String
    let selector: Selector
    /// Passed to the action as its sender's `argument` (a Settings page, a mode, a layout).
    var argument: String?
    var kind = Kind.command
    /// Where a setting lives ("Settings · Appearance"), shown at the row's end instead of a shortcut.
    var detail = ""

    static let scheme = "ikago-action:"
    var url: String { Self.scheme + id }

    init?(url: String) {
        guard url.hasPrefix(Self.scheme), let action = Self.all.first(where: { $0.url == url }) else { return nil }
        self = action
    }

    init(_ id: String, _ title: String, _ symbol: String, _ shortcut: String = "", _ keywords: String = "", _ action: String,
         argument: String? = nil, kind: Kind = .command, detail: String = "") {
        self.id = id; self.title = title; self.symbol = symbol; self.shortcut = shortcut; self.keywords = keywords
        selector = NSSelectorFromString(action)
        self.argument = argument; self.kind = kind; self.detail = detail
    }

    /// Every setting in Settings, registered once by the UI (it owns the settings index).
    nonisolated(unsafe) static var settings: [PaletteAction] = []
    static var all: [PaletteAction] { builtIn + settings }

    /// Actions where every typed word starts a word of the name or keywords, in any order ("delete history" finds Clear
    /// Browsing History), best first: the whole name typed, then words of the name, then keywords; commands before
    /// settings of the same score.
    static func matching(_ text: String) -> [PaletteAction] {
        let query = text.lowercased().trimmingCharacters(in: .whitespaces)
        let typed = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard query.count >= 2, !typed.isEmpty else { return [] }
        func words(_ text: String) -> [String] {
            text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        }
        func score(_ action: PaletteAction) -> Int {
            let title = words(action.title), all = title + words(action.keywords)
            guard typed.allSatisfy({ word in all.contains { $0.hasPrefix(word) } }) else { return 0 }
            let base = action.title.lowercased().hasPrefix(query) ? 6 : typed.allSatisfy({ word in title.contains { $0.hasPrefix(word) } }) ? 4 : 2
            return base + (action.kind == .command ? 1 : 0)
        }
        return all.map { ($0, score($0)) }.filter { $0.1 > 0 }.enumerated()
            .sorted { $0.element.1 == $1.element.1 ? $0.offset < $1.offset : $0.element.1 > $1.element.1 }
            .map(\.element.0)
    }

    /// Runs the action in `window` (its controller, or the window itself), as its menu item would there. Aimed, not
    /// sent down the responder chain, which depends on whichever window happens to be key.
    @MainActor func perform(in window: NSWindow?) {
        let candidates: [AnyObject] = [window?.windowController, window].compactMap { $0 }
        let target = candidates.first { $0.responds(to: selector) }
        NSApp.sendAction(selector, to: target, from: PaletteActionSender(argument: argument))
    }
}

/// The sender an action receives, carrying its argument.
final class PaletteActionSender: NSObject {
    let argument: String?
    init(argument: String?) { self.argument = argument }
}
