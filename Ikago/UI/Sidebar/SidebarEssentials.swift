import SwiftUI

struct SidebarEssentials: View {
    let state: BrowserState
    let chrome: ChromeModel
    weak var commands: BrowserCommands?
    var onSelection: (() -> Void)? = nil
    @State private var columnCount = 3

    var body: some View {
        if state.showsPinnedGrid && !state.pinnedTabs.isEmpty {
            SidebarScrollView(chrome: chrome) {
                PinnedTabsGrid(state: state, chrome: chrome, commands: commands,
                               onSelection: onSelection, columnCount: columnCount)
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .openTabDrop(state: state, chrome: chrome) { id, _ in state.move(id, before: nil, pinned: true) }
                    .padding(.vertical, 2)
            }
            .frame(height: min(220, CGFloat(max(1, (state.pinnedTabs.count + columnCount - 1) / columnCount)) * 50 - 4))
            .onGeometryChange(for: Int.self) { geometry in
                // At least 64 pt per tile, with 8 pt gaps; never exceed three columns.
                min(3, max(1, Int((geometry.size.width + 8) / 72)))
            } action: { columnCount = $0 }
        }
    }
}

/// Where a dragged tab can be pinned while there are no essentials yet. It floats over the top of the tab list
/// instead of being inserted above it, so the list doesn't jump under the pointer when a drag starts and ends.
struct EmptyEssentialsDropZone: View {
    let state: BrowserState
    let chrome: ChromeModel

    var body: some View {
        if state.showsPinnedGrid && state.pinnedTabs.isEmpty && chrome.draggingTabID != nil {
            let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
            shape.fill(state.palette.selected)
                .overlay(shape.strokeBorder(state.palette.separator, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                .frame(height: 42)
                .openTabDrop(state: state, chrome: chrome) { id, _ in state.move(id, before: nil, pinned: true) }
                .transition(.opacity)
        }
    }
}
