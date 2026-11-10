import SwiftUI

struct BookmarkEditor: View {
    let state: BrowserState
    let bookmark: Bookmark
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var address: String
    @State private var folderID: String

    init(state: BrowserState, bookmark: Bookmark) {
        self.state = state; self.bookmark = bookmark
        _title = State(initialValue: bookmark.title)
        _address = State(initialValue: bookmark.url)
        _folderID = State(initialValue: bookmark.folderID ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Bookmark").font(.headline)
            TextField("Title", text: $title)
            TextField("https://example.com", text: $address)
            Picker("Folder", selection: $folderID) {
                Text("Bookmarks Bar").tag("")
                ForEach(state.bookmarkFolderChoices, id: \.id) { choice in Text(choice.path).tag(choice.id) }
            }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    state.updateBookmark(bookmark.id, title: title, url: address, folderID: folderID.isEmpty ? nil : folderID)
                    dismiss()
                }
                .disabled(!AddressResolver.isWebURL(address) || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 380)
    }
}
