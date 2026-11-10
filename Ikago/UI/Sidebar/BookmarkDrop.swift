import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct BookmarkDrag: Codable, Transferable {
    let id: String
    static var transferRepresentation: some TransferRepresentation { CodableRepresentation(contentType: .ikagoBookmark) }
}

extension UTType { static let ikagoBookmark = UTType(exportedAs: "app.ikago.bookmark") }

extension View {
    /// Saving an open tab here keeps the tab alive.
    func bookmarkDrop(state: BrowserState, chrome: ChromeModel?, folderID: String?) -> some View {
        onDrop(of: [.ikagoBookmark, .ikagoTab], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            if provider.hasItemConformingToTypeIdentifier(UTType.ikagoTab.identifier) {
                TabDrag.load(provider) { id in
                    chrome?.endTabDrag()
                    guard let tab = state.tab(id), AddressResolver.isWebURL(tab.url) else { return }
                    state.addBookmark(tab)
                    if let bookmark = state.bookmarks.first(where: { $0.url == tab.url }) { state.moveBookmark(bookmark.id, to: folderID) }
                }
            } else {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.ikagoBookmark.identifier) { data, _ in
                    guard let data, let drag = try? JSONDecoder().decode(BookmarkDrag.self, from: data) else { return }
                    Task { @MainActor in state.moveBookmark(drag.id, to: folderID) }
                }
            }
            return true
        }
    }
}
