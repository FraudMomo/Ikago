import AppKit

/// A shortcut the person chose for a menu command (Settings ▸ General ▸ Keyboard Shortcuts). `key` empty: no shortcut.
struct KeyCombo: Codable, Equatable, Hashable {
    var key: String
    /// `NSEvent.ModifierFlags` raw value (command, option, control, shift only).
    var modifiers: UInt

    static let none = KeyCombo(key: "", modifiers: 0)
    static let allowedFlags: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers).intersection(Self.allowedFlags) }
    var isEmpty: Bool { key.isEmpty }
    /// Menu shortcuts reach the menu only with ⌘ or ⌃ (`ShortcutRouter`), and keys alone would steal typing.
    var isUsable: Bool { !key.isEmpty && !flags.intersection([.command, .control]).isEmpty }

    /// "⇧⌘K", in the menu's own order.
    var display: String {
        guard !key.isEmpty else { return "" }
        var text = ""
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        return text + Self.name(of: key)
    }

    static func name(of key: String) -> String {
        switch key {
        case "\t": "⇥"
        case "\r": "↩"
        case " ": "Space"
        case String(UnicodeScalar(NSLeftArrowFunctionKey)!): "←"
        case String(UnicodeScalar(NSRightArrowFunctionKey)!): "→"
        case String(UnicodeScalar(NSUpArrowFunctionKey)!): "↑"
        case String(UnicodeScalar(NSDownArrowFunctionKey)!): "↓"
        case "\u{8}", "\u{7f}": "⌫"
        default: key.uppercased()
        }
    }

    /// The combo a key press makes, or nil for a press that can't be a shortcut (modifiers alone).
    init?(event: NSEvent) {
        guard let characters = event.charactersIgnoringModifiers?.lowercased(), !characters.isEmpty else { return nil }
        let flags = event.modifierFlags.intersection(Self.allowedFlags)
        // Shift changes the character (⇧1 is "!"); keep the unshifted key, as the menu does.
        let key = flags.contains(.shift) ? (event.charactersIgnoringModifiers ?? characters).lowercased() : characters
        self.init(key: key, modifiers: flags.rawValue)
    }

    init(key: String, modifiers: UInt) {
        self.key = key
        self.modifiers = modifiers
    }
}

/// Every menu command with a shortcut the person can change: an id from its action (and which copy, for commands
/// listed twice), its place in the menu, and its built-in shortcut. Bindings live in `BrowserPreferences.keyBindings`
/// by id and are applied to the menu, which stays the one source of shortcuts (`ShortcutRouter`).
@MainActor
enum KeyBindings {
    /// The identifier prefix `MainMenu` gives Ikago's own items.
    nonisolated static let ownPrefix = "ikago."

    struct Command: Identifiable {
        let id: String
        let title: String
        let menu: String
        let defaultCombo: KeyCombo
        fileprivate weak var item: NSMenuItem?
    }

    /// Set while Settings records a shortcut: the key monitor hands presses to it instead of the menu or the page.
    static var recorder: ((NSEvent) -> Void)?
    /// The window recording: presses in any other window go on as usual, so a recorder left behind can't eat typing.
    static weak var recordingWindow: NSWindow?
    /// Each item's built-in shortcut exactly as built (key and the whole modifier mask, fn included), to put back.
    private static var defaults: [ObjectIdentifier: (key: String, mask: NSEvent.ModifierFlags)] = [:]
    private static var applied: [String: KeyCombo]?? = .none

    /// The commands in menu order (Ikago's own menus; system ones like Cut and Copy stay as they are).
    static var commands: [Command] {
        var out: [Command] = []
        var seen: [String: Int] = [:]
        guard let main = NSApp.mainMenu else { return [] }
        func visit(_ menu: NSMenu, path: String) {
            for item in menu.items {
                if let sub = item.submenu { visit(sub, path: path.isEmpty ? item.title : path); continue }
                // Ikago's own items only: macOS adds its own to the menus, with fn shortcuts this must never touch.
                guard let action = item.action, !item.isSeparatorItem, !item.title.isEmpty,
                      item.identifier?.rawValue.hasPrefix(ownPrefix) == true,
                      !excluded.contains(NSStringFromSelector(action)) else { continue }
                let base = NSStringFromSelector(action) + (item.tag != 0 ? "#\(item.tag)" : "")
                let copy = seen[base, default: 0]
                seen[base] = copy + 1
                out.append(Command(id: copy == 0 ? base : "\(base)@\(copy)", title: item.title, menu: path,
                                   defaultCombo: defaultCombo(of: item), item: item))
            }
        }
        visit(main, path: "")
        return out
    }

    /// Edit and app-level items whose keys every Mac app shares.
    private static let excluded: Set<String> = [
        "undo:", "redo:", "cut:", "copy:", "paste:", "selectAll:", "terminate:", "hide:", "hideOtherApplications:",
        "orderFrontStandardAboutPanel:", "performClose:", "performMiniaturize:",
    ]

    private static func defaultCombo(of item: NSMenuItem) -> KeyCombo {
        let built = builtIn(item)
        return KeyCombo(key: built.key, modifiers: built.key.isEmpty ? 0 : built.mask.rawValue)
    }

    private static func builtIn(_ item: NSMenuItem) -> (key: String, mask: NSEvent.ModifierFlags) {
        let key = ObjectIdentifier(item)
        if let saved = defaults[key] { return saved }
        let built = (item.keyEquivalent, item.keyEquivalentModifierMask)
        defaults[key] = built
        return built
    }

    /// Puts the person's shortcuts on the menu (and the built-in ones back where they have none).
    static func apply(_ bindings: [String: KeyCombo]?) {
        // Preferences change often (any setting); the menu only when the shortcuts did.
        if case .some(let last) = applied, last == bindings { return }
        applied = .some(bindings)
        for command in commands {
            guard let item = command.item else { continue }
            // Always both, and the built-in one exactly as built: a refused shortcut reads back empty while AppKit still
            // holds it, so a comparison would skip the change that takes it away.
            if let combo = bindings?[command.id], combo.isUsable || combo.isEmpty {
                item.keyEquivalentModifierMask = combo.isEmpty ? [] : combo.flags
                item.keyEquivalent = combo.key
            } else {
                let built = builtIn(item)
                item.keyEquivalentModifierMask = built.mask
                item.keyEquivalent = built.key
            }
        }
    }

    /// Whether the menu took `id`'s shortcut: AppKit quietly refuses one another menu item already has, even one Ikago
    /// doesn't list (Edit's, the app menu's).
    static func menuHas(_ id: String, _ combo: KeyCombo) -> Bool {
        guard let item = commands.first(where: { $0.id == id })?.item else { return false }
        return item.keyEquivalent == combo.key && (combo.isEmpty || item.keyEquivalentModifierMask == combo.flags)
    }

    /// The shortcut a command has now.
    static func current(_ id: String, bindings: [String: KeyCombo]?) -> KeyCombo {
        bindings?[id] ?? commands.first { $0.id == id }?.defaultCombo ?? .none
    }

    /// Another command already using `combo`, if any.
    static func conflict(for combo: KeyCombo, except id: String, bindings: [String: KeyCombo]?) -> Command? {
        guard !combo.isEmpty else { return nil }
        return commands.first { $0.id != id && current($0.id, bindings: bindings) == combo }
    }

    /// The command bar's shortcut as shown in hints ("⇧⌘K"), following the person's choice.
    static func display(for action: Selector) -> String {
        let id = NSStringFromSelector(action)
        return current(id, bindings: BrowserSecurity.shared.preferences.keyBindings).display
    }
}
