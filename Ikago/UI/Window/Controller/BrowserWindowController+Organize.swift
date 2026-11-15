import AppKit
import SwiftUI
import WebKit

// MARK: - Organize
/// Spaces, folders and the Library panel: the commands behind the sidebar's organising UI.
extension BrowserWindowController {
    // MARK: Spaces

    func newSpace() {
        chrome.showNewSpace = true
    }

    func customizeFolder(_ id: String) { chrome.editFolderID = id }

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
        guard let browser = window?.windowController as? BrowserWindowController else { return nil }
        return await withCheckedContinuation { continuation in
            browser.chrome.textPrompt?.finish(nil)
            browser.chrome.textPrompt = IntegratedTextPrompt(title: title, placeholder: value) { result in
                browser.chrome.textPrompt = nil
                continuation.resume(returning: result)
            }
        }
    }
}

// MARK: - Bookmarks
extension BrowserWindowController {
    func newBookmarkFolder(parentID: String?) {
        Task {
            if let name = await TextPrompt.ask("New Bookmark Folder", value: "", in: window) {
                withAnimation(.ikago) { _ = state.createBookmarkFolder(named: name, parentID: parentID) }
            }
        }
    }

    func renameBookmarkFolder(_ id: String) {
        guard let folder = state.bookmarkFolders.first(where: { $0.id == id }) else { return }
        Task {
            if let name = await TextPrompt.ask("Rename Bookmark Folder", value: folder.name, in: window) {
                state.renameBookmarkFolder(id, to: name)
            }
        }
    }

    func editBookmark(_ bookmark: Bookmark) { chrome.bookmarkToEdit = bookmark }

    @objc func toggleBookmarksBar(_ sender: Any?) {
        withAnimation(.ikago) { state.showsBookmarksBar.toggle() }
    }
}

// MARK: - Spaces
extension BrowserWindowController {
    func setSpaceShared(_ id: UUID, shared: Bool) {
        guard let index = state.spaces.firstIndex(where: { $0.id == id }), state.spaces[index].isolated != !shared else { return }
        let active = state.activeTabID.flatMap(state.tab)?.spaceID == id ? state.activeTabID : nil
        if active != nil { state.activeTabID = nil }
        let ids = state.tabs.filter { $0.spaceID == id }.map(\.id)
        for tabID in ids { content.controller(for: tabID)?.hibernate() }
        state.spaces[index].isolated = !shared
        if let active { state.activeTabID = active }
        state.scheduleSave()
    }
}

// MARK: - Selection
/// Several tabs picked together (`TabClick`, `ChromeModel.selectedTabIDs`): what their menu does with them all.
extension BrowserWindowController {
    func tabSelection(including id: String) -> [String] { TabClick.group(including: id, state: state, chrome: chrome) }

    func moveTabsToNewWindow(_ ids: [String]) {
        chrome.selectedTabIDs = []
        BrowserWindows.moveToNewWindow(ids, from: self)
    }

    func closeTabs(_ ids: [String]) {
        chrome.selectedTabIDs = []
        for id in ids { closeTab(id) }
    }

    func moveTabs(_ ids: [String], toFolder folderID: String?) {
        chrome.selectedTabIDs = []
        for id in ids { state.moveToFolder(id, folderID: folderID) }
    }

    /// A new group holding the tabs, named by the person.
    func newFolder(withTabs ids: [String]) {
        Task {
            guard let name = await TextPrompt.ask("New Group", value: "", in: window) else { return }
            let folder = state.createFolder(named: name, with: ids.first)
            for id in ids.dropFirst() { state.moveToFolder(id, folderID: folder.id) }
            chrome.selectedTabIDs = []
        }
    }
}

// MARK: - Files
extension BrowserWindowController {
    func openDroppedFiles(_ urls: [URL]) {
        let files = urls.filter { AddressResolver.isLocalFileURL($0.absoluteString) }
        guard let first = files.first else { return }
        dismissCommandPalette()
        // Preserve pinned pages through the shared address-navigation guard.
        open(first.absoluteString, inNewTab: false)
        for file in files.dropFirst() { _ = state.newTab(url: file.absoluteString, select: false) }
        window?.makeKeyAndOrderFront(nil)
    }
}
