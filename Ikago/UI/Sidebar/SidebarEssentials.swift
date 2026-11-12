import SwiftUI

struct SidebarEssentials: View {
    let state: BrowserState
    let chrome: ChromeModel
    weak var commands: BrowserCommands?
    var onSelection: (() -> Void)? = nil
    @State private var availableColumns = 1
    private var columnCount: Int { min(state.browserPreferences.pinnedGridColumns ?? 3, availableColumns) }

    var body: some View {
        if state.showsPinnedGrid && !state.sidebarGridPinnedTabs.isEmpty {
            SidebarScrollView(chrome: chrome) {
                PinnedTabsGrid(state: state, chrome: chrome, commands: commands,
                               onSelection: onSelection, columnCount: columnCount)
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .openTabDrop(state: state, chrome: chrome) { id, _ in state.move(id, before: nil, pinned: true) }
                    .padding(.vertical, 2)
                    .contextMenu {
                        Picker("Grid size", selection: Binding(
                            get: { state.browserPreferences.pinnedGridColumns ?? 3 },
                            set: { state.browserPreferences.pinnedGridColumns = $0 }
                        )) {
                            ForEach(2...8, id: \.self) { count in Text("\(count) columns").tag(count) }
                        }
                    }
            }
            .frame(height: min(220, CGFloat(max(1, (state.sidebarGridPinnedTabs.count + columnCount - 1) / columnCount)) * 50 - 4))
            .onGeometryChange(for: Int.self) { geometry in
                max(1, Int(geometry.size.width / 44))
            } action: { availableColumns = $0 }
        }
    }
}

/// Where a dragged tab can be pinned while there are no essentials yet. It floats over the top of the tab list
/// instead of being inserted above it, so the list doesn't jump under the pointer when a drag starts and ends.
struct EmptyEssentialsDropZone: View {
    let state: BrowserState
    let chrome: ChromeModel

    var body: some View {
        if state.showsPinnedGrid && state.sidebarGridPinnedTabs.isEmpty && chrome.draggingTabID != nil {
            let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
            shape.fill(state.palette.selected)
                .overlay(shape.strokeBorder(state.palette.separator, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                .frame(height: 42)
                .openTabDrop(state: state, chrome: chrome) { id, _ in state.move(id, before: nil, pinned: true) }
                .transition(.opacity)
        }
    }
}
