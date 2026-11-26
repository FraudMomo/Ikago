#if DEBUG
import AppKit

/// Changeable shortcuts: the command bar's default, a change reaching the menu, refusing one in use, and resets.
@MainActor
enum ShortcutChecks {
    static func run(_ browser: BrowserWindowController) {
        let state = browser.state
        var failures = 0
        func check(_ value: Bool, _ title: String) {
            print("IKTEST shortcuts \(value ? "PASS" : "FAIL") \(title)")
            if !value { failures += 1 }
        }
        let saved = state.browserPreferences.keyBindings
        let id = NSStringFromSelector(#selector(BrowserWindowController.openCommandBar(_:)))
        func item() -> NSMenuItem? {
            var found: NSMenuItem?
            func visit(_ menu: NSMenu) { for i in menu.items { if i.action == #selector(BrowserWindowController.openCommandBar(_:)) { found = i }; i.submenu.map(visit) } }
            NSApp.mainMenu.map(visit)
            return found
        }
        state.browserPreferences.keyBindings = nil
        KeyBindings.apply(nil)
        check(item()?.keyEquivalent == "k" && item()?.keyEquivalentModifierMask == [.command, .shift],
              "the command bar is ⇧⌘K by default, not ⌘K")
        let custom = KeyCombo(key: "u", modifiers: NSEvent.ModifierFlags([.command, .option]).rawValue)
        state.browserPreferences.keyBindings = [id: custom]
        KeyBindings.apply(state.browserPreferences.keyBindings)
        check(item()?.keyEquivalent == "u" && item()?.keyEquivalentModifierMask == [.command, .option] && KeyBindings.menuHas(id, custom),
              "a changed shortcut reaches the menu")
        let builtIn = KeyCombo(key: "j", modifiers: NSEvent.ModifierFlags([.command, .option]).rawValue)
        KeyBindings.apply([id: builtIn])
        check(!KeyBindings.menuHas(id, builtIn), "a shortcut another menu item has is noticed as not taken")
        let taken = KeyCombo(key: "t", modifiers: NSEvent.ModifierFlags.command.rawValue)
        check(KeyBindings.conflict(for: taken, except: id, bindings: state.browserPreferences.keyBindings)?.title == "New Tab",
              "a shortcut another command uses is found")
        check(!KeyCombo(key: "j", modifiers: NSEvent.ModifierFlags.option.rawValue).isUsable, "a shortcut without ⌘ or ⌃ is refused")
        state.browserPreferences.keyBindings = [id: .none]
        KeyBindings.apply(state.browserPreferences.keyBindings)
        check(item()?.keyEquivalent == "", "a removed shortcut leaves the command without one")
        state.browserPreferences.keyBindings = saved
        KeyBindings.apply(saved)
        check(saved != nil || item()?.keyEquivalent == "k", "reset puts the built-in shortcut back")
        // No menu item, Ikago's or macOS's, may fire on a key alone: a bare letter would run while typing on pages (plain
        // D started dictation and E the emoji picker when built-in items lost their fn).
        var bare: [String] = []
        func visit(_ menu: NSMenu) {
            for item in menu.items {
                if let sub = item.submenu { visit(sub); continue }
                let mask = item.keyEquivalentModifierMask.intersection([.command, .control, .option, .function])
                let special = item.keyEquivalent.unicodeScalars.first.map { $0.value >= 0xF700 || $0.value == 27 } ?? true
                if !item.keyEquivalent.isEmpty, mask.isEmpty, !special { bare.append(item.title) }
            }
        }
        NSApp.mainMenu.map(visit)
        check(bare.isEmpty, "no menu item fires on a key alone (\(bare.joined(separator: ", ")))")
        print("IKTEST shortcutchecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }
}
#endif
