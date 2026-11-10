import AppKit
import SwiftUI
import WebKit

/// Spaces, folders and the Library panel: the commands behind the sidebar's organising UI.
extension BrowserWindowController {
    // MARK: Spaces

    func newSpace() {
        guard let window, window.attachedSheet == nil else { return }
        var sheet: NSWindow?
        let view = NewSpaceView(onCreate: { [weak self] name, symbol, isolated in
            self?.state.createSpace(name: name, symbol: symbol, isolated: isolated)
            if let sheet { window.endSheet(sheet) }
        }, onCancel: {
            if let sheet { window.endSheet(sheet) }
        })
        sheet = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.beginSheet(sheet!)
    }

    func renameSpace(_ id: UUID) {
        guard let space = state.spaces.first(where: { $0.id == id }) else { return }
        Task {
            if let name = await TextPrompt.ask("Rename Space", value: space.name, in: window) {
                state.renameSpace(id, to: name)
            }
        }
    }

    /// Confirms, then deletes the Space's tabs, and for an isolated Space its website data.
    func deleteSpace(_ id: UUID) {
        guard let space = state.spaces.first(where: { $0.id == id }), state.spaces.count > 1 else { return }
        Task {
            let alert = NSAlert()
            alert.messageText = "Delete “\(space.name)”?"
            alert.informativeText = space.isolated
                ? "Its tabs close, and its logins, cookies and site data are erased."
                : "Its tabs and groups close."
            alert.addButton(withTitle: "Delete Space")
            alert.addButton(withTitle: "Cancel")
            alert.buttons.first?.hasDestructiveAction = true
            guard let window, await alert.beginSheetModal(for: window) == .alertFirstButtonReturn else { return }
            state.deleteSpace(id)
            if space.isolated {
                // Erase it from both engines: its data may be in either after a switch.
                CEFSessions.scheduleProfileRemoval(space.profileID)
                await WebProfiles.clearWebKitWebsiteData(space.profileID)
            }
        }
    }

    @objc func newSpaceAction(_ sender: Any?) { newSpace() }
    @objc func newPrivateWindow(_ sender: Any?) { (NSApp.delegate as? AppDelegate)?.openPrivateWindow() }
    @objc func nextSpace(_ sender: Any?) { state.selectAdjacentSpace(1) }
    @objc func previousSpace(_ sender: Any?) { state.selectAdjacentSpace(-1) }

    // MARK: Folders

    /// New folder in the active Space, holding `tabID` if given.
    func newFolder(with tabID: String?) {
        Task {
            if let name = await TextPrompt.ask("New Group", value: "", in: window) {
                state.createFolder(named: name, with: tabID)
            }
        }
    }

    func renameFolder(_ id: String) {
        guard let folder = state.folders.first(where: { $0.id == id }) else { return }
        Task {
            if let name = await TextPrompt.ask("Rename Group", value: folder.name, in: window) {
                state.renameFolder(id, to: name)
            }
        }
    }

    /// The emoji viewer opens beside the field, so one click picks one; only the first emoji counts.
    func chooseFolderEmoji(_ id: String) {
        guard let folder = state.folders.first(where: { $0.id == id }) else { return }
        Task {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { NSApp.orderFrontCharacterPalette(nil) }
            guard let text = await TextPrompt.ask("Group Emoji", value: folder.emojiIcon ?? "", in: window),
                  let first = text.first, first.unicodeScalars.contains(where: { $0.properties.isEmoji && ($0.properties.isEmojiPresentation || $0.value > 0x238C) })
            else { return }
            withAnimation(.ikago) { state.setFolderIcon(id, to: String(first)) }
        }
    }
}

/// One-line text input as a sheet. Returns nil when cancelled or empty.
@MainActor
enum TextPrompt {
    static func ask(_ title: String, value: String, in window: NSWindow?) async -> String? {
        let alert = NSAlert()
        alert.messageText = title
        let field = NSTextField(string: value)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        let response: NSApplication.ModalResponse
        if let window, window.attachedSheet == nil { response = await alert.beginSheetModal(for: window) } else { response = alert.runModal() }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return response == .alertFirstButtonReturn && !text.isEmpty ? String(text.prefix(60)) : nil
    }
}
