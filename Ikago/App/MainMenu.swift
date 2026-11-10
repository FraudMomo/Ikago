import AppKit

/// The app menu bar — the single source of truth for keyboard shortcuts.
@MainActor
enum MainMenu {
    static func build() -> NSMenu {
        let main = NSMenu()
        main.addSubmenu("Ikago") {
            $0.item("About Ikago", #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
            $0.separator()
            $0.item("Settings…", #selector(BrowserWindowController.showIkagoSettings(_:)), ",")
            $0.separator()
            $0.item("Hide Ikago", #selector(NSApplication.hide(_:)), "h")
            $0.item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option])
            $0.separator()
            $0.item("Quit Ikago", #selector(NSApplication.terminate(_:)), "q")
        }
        main.addSubmenu("File") {
            $0.item("New Tab", #selector(BrowserWindowController.newTab(_:)), "t")
            $0.item("New Space…", #selector(BrowserWindowController.newSpaceAction(_:)), "n", [.command, .shift])
            $0.item("New Private Window", #selector(BrowserWindowController.newPrivateWindow(_:)), "n", [.command, .option])
            $0.item("Open Location…", #selector(BrowserWindowController.openLocation(_:)), "l")
            $0.item("Reopen Closed Tab", #selector(BrowserWindowController.reopenClosedTab(_:)), "t", [.command, .shift])
            $0.separator()
            $0.item("Close Tab", #selector(BrowserWindowController.closeCurrentTab(_:)), "w")
            $0.item("Close Window", #selector(NSWindow.performClose(_:)), "w", [.command, .shift])
            $0.separator()
            $0.item("Print…", #selector(BrowserWindowController.printCurrentPage(_:)), "p")
        }
        main.addSubmenu("Edit") {
            $0.item("Undo", Selector(("undo:")), "z")
            $0.item("Redo", Selector(("redo:")), "z", [.command, .shift])
            $0.separator()
            $0.item("Cut", #selector(NSText.cut(_:)), "x")
            $0.item("Copy", #selector(NSText.copy(_:)), "c")
            $0.item("Paste", #selector(NSText.paste(_:)), "v")
            $0.item("Select All", #selector(NSText.selectAll(_:)), "a")
            $0.separator()
            $0.item("Copy Page Address", #selector(BrowserWindowController.copyPageAddress(_:)), "c", [.command, .shift])
            $0.item("Find…", #selector(BrowserWindowController.findInPage(_:)), "f")
            $0.item("Find Next", #selector(BrowserWindowController.findNextMatch(_:)), "g")
            $0.item("Find Previous", #selector(BrowserWindowController.findPreviousMatch(_:)), "g", [.command, .shift])
        }
        main.addSubmenu("View") {
            $0.item("Hide Sidebar", #selector(BrowserWindowController.toggleIkagoSidebar(_:)), "s", [.command, .shift])
            $0.item("Compact Sidebar", #selector(BrowserWindowController.toggleCompactSidebar(_:)), "s", [.command, .control])
            $0.separator()
            $0.item("Reload Page", #selector(BrowserWindowController.reloadPage(_:)), "r")
            $0.item("Stop Loading", #selector(BrowserWindowController.stopLoadingPage(_:)), ".")
            $0.item("Hard Reload", #selector(BrowserWindowController.hardReloadPage(_:)), "r", [.command, .shift])
            $0.separator()
            $0.item("Zoom In", #selector(BrowserWindowController.zoomInPage(_:)), "+")
            $0.item("Zoom Out", #selector(BrowserWindowController.zoomOutPage(_:)), "-")
            $0.item("Actual Size", #selector(BrowserWindowController.resetPageZoom(_:)), "0")
            $0.separator()
            $0.item("Split View", #selector(BrowserWindowController.splitView(_:)), "d", [.command, .shift])
            $0.item("Rotate Split", #selector(BrowserWindowController.toggleSplitOrientation(_:)), "d", [.command, .option])
            $0.item("Close Split View", #selector(BrowserWindowController.unsplitView(_:)))
            $0.separator()
            $0.addSubmenu("Tab Layout") { menu in
                for (index, layout) in TabLayout.allCases.enumerated() {
                    menu.item(layout.name, #selector(BrowserWindowController.selectLayout(_:))).tag = index
                }
            }
            $0.addSubmenu("Appearance") { menu in
                for (index, mode) in ColorMode.allCases.enumerated() {
                    menu.item(mode.name, #selector(BrowserWindowController.selectColorMode(_:))).tag = index
                }
            }
            $0.separator()
            $0.item("Developer Tools", #selector(BrowserWindowController.toggleDevTools(_:)), "i", [.command, .option])
            $0.item("Performance Stats", #selector(BrowserWindowController.togglePerformanceStats(_:)))
            $0.item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control])
        }
        main.addSubmenu("History") {
            $0.item("Back", #selector(BrowserWindowController.navigateBack(_:)), "[")
            $0.item("Forward", #selector(BrowserWindowController.navigateForward(_:)), "]")
            $0.separator()
            $0.item("Show All History", #selector(BrowserWindowController.showHistory(_:)), "y")
            $0.item("Downloads", #selector(BrowserWindowController.showDownloads(_:)), "j", [.command, .shift])
        }
        main.addSubmenu("Bookmarks") {
            $0.item("Show Bookmarks Bar", #selector(BrowserWindowController.toggleBookmarksBar(_:)), "b", [.command, .shift])
            $0.separator()
            $0.item("Bookmark This Page", #selector(BrowserWindowController.bookmarkPage(_:)), "d")
            $0.item("Show Bookmarks", #selector(BrowserWindowController.showBookmarks(_:)), "b", [.command, .option])
        }
        main.addSubmenu("Tab") {
            $0.item("Next Tab", #selector(BrowserWindowController.nextTab(_:)), "\t", [.control])
            $0.item("Previous Tab", #selector(BrowserWindowController.previousTab(_:)), "\t", [.control, .shift])
            $0.item("Next Tab", #selector(BrowserWindowController.nextTab(_:)), "}", [.command])
            $0.item("Previous Tab", #selector(BrowserWindowController.previousTab(_:)), "{", [.command])
            $0.separator()
            $0.item("Next Space", #selector(BrowserWindowController.nextSpace(_:)), "]", [.command, .control])
            $0.item("Previous Space", #selector(BrowserWindowController.previousSpace(_:)), "[", [.command, .control])
            $0.separator()
            let groups = $0.addSubmenu("Reopen Closed Group") { _ in }
            groups.delegate = ClosedGroupsMenu.shared
            $0.separator()
            $0.item("Pin Tab — Keep This Tab", #selector(BrowserWindowController.togglePinTab(_:)))
            $0.item("Mute Tab", #selector(BrowserWindowController.toggleMuteTab(_:)), "m", [.command, .control])
            $0.separator()
            for n in 1...9 {
                $0.item(n == 9 ? "Last Tab" : "Tab \(n)", #selector(BrowserWindowController.selectTabByNumber(_:)), "\(n)").tag = n
            }
        }
        let window = main.addSubmenu("Window") {
            $0.item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m")
            $0.item("Zoom", #selector(NSWindow.performZoom(_:)))
        }
        NSApp.windowsMenu = window
        return main
    }
}

/// Decides which key-downs the app takes before the web page sees them.
@MainActor
enum ShortcutRouter {
    /// Page editing shortcuts stay with the page; everything else in the menu wins.
    private static let pageKeys: Set<String> = ["c", "v", "x", "a", "z"]

    static func intercept(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command) || flags.contains(.control) else { return false }
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if flags.subtracting([.capsLock, .numericPad, .function]) == .command, pageKeys.contains(key) { return false }
        return NSApp.mainMenu?.performKeyEquivalent(with: event) ?? false
    }
}

/// Fills Tab ▸ Reopen Closed Group with the key window's closed groups each time it opens.
@MainActor
final class ClosedGroupsMenu: NSObject, NSMenuDelegate {
    static let shared = ClosedGroupsMenu()

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let state = (NSApp.keyWindow?.windowController as? BrowserWindowController)?.state
        let folders = state?.closedFolders ?? []
        if folders.isEmpty {
            let empty = NSMenuItem(title: "No Closed Groups", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for folder in folders {
            let count = state?.tabs(in: folder).count ?? 0
            let item = NSMenuItem(title: "\(folder.name) (\(count) \(count == 1 ? "tab" : "tabs"))",
                                  action: #selector(BrowserWindowController.reopenGroup(_:)), keyEquivalent: "")
            item.representedObject = folder.id
            menu.addItem(item)
        }
    }
}

private extension NSMenu {
    @discardableResult
    func addSubmenu(_ title: String, _ build: (NSMenu) -> Void) -> NSMenu {
        let menu = NSMenu(title: title)
        build(menu)
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        addItem(item)
        return menu
    }

    @discardableResult
    func item(_ title: String, _ action: Selector, _ key: String = "",
              _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = key.isEmpty ? [] : modifiers
        addItem(item)
        return item
    }

    func separator() { addItem(.separator()) }
}
