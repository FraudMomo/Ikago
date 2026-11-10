import AppKit

@MainActor
enum CEFShortcutChecks {
    /// Explicit menu targets avoid activating a hidden window. Dispatch still uses
    /// the production key classifier and real NSMenu key-equivalent resolution.
    static func dispatch(_ key: String, modifiers: NSEvent.ModifierFlags = .command,
                         shell: BrowserWindowController) throws -> Bool {
        let previous = NSApp.mainMenu
        let menu = MainMenu.build()
        func target(_ menu: NSMenu) {
            for item in menu.items {
                if let action = item.action, shell.responds(to: action) { item.target = shell }
                if let submenu = item.submenu { target(submenu) }
            }
        }
        target(menu)
        NSApp.mainMenu = menu
        defer { NSApp.mainMenu = previous }
        guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: shell.window!.windowNumber,
            context: nil, characters: key, charactersIgnoringModifiers: key, isARepeat: false, keyCode: 0) else { throw CEFError.noResult }
        return ShortcutRouter.intercept(event)
    }
    static func editingKeysStayWithPage(_ shell: BrowserWindowController) throws {
        for key in ["c", "v", "x", "a", "z"] {
            guard try !dispatch(key, shell: shell) else { throw CEFError.script("The browser intercepted a page editing shortcut.") }
        }
        print("CEF_SHORTCUTS_OK menu-equivalents address close reopen page-editing-pass-through")
    }
}
