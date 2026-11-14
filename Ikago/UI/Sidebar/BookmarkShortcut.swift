import SwiftUI

struct BookmarkShortcut: View {
    let bookmark: Bookmark
    let state: BrowserState
    let colors: Palette
    weak var commands: BrowserCommands?
    var sidebar = false
    @State private var hovering = false

    var body: some View {
        Button { commands?.openBookmark(bookmark, forceNewTab: false) } label: {
            HStack(spacing: 7) {
                FaviconView(pageURL: bookmark.url, iconURL: bookmark.favicon, size: 13)
                Text(bookmark.title).font(.system(size: 12)).lineLimit(1)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: sidebar ? .infinity : 160, alignment: .leading)
            .frame(height: 28).contentShape(Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(colors.text.opacity(0.85))
        .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(hovering ? colors.hover : .clear))
        .onHover { hovering = $0 }
        .animation(.ikagoQuick, value: hovering)
        .contextMenu { BookmarkContextMenu(bookmark: bookmark, state: state, commands: commands) }
        .draggable(BookmarkDrag(id: bookmark.id))
        .onMiddleClick { commands?.openBookmark(bookmark, forceNewTab: true) }
        .help("\(bookmark.title)\n\(bookmark.url)")
    }
}
