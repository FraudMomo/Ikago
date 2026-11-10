import AppKit
import SwiftUI

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
