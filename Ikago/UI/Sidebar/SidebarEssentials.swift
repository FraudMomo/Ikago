import SwiftUI
import UniformTypeIdentifiers

// MARK: - Essentials
struct SidebarEssentials: View {
    let state: BrowserState
    let chrome: ChromeModel
    weak var commands: BrowserCommands?
    var onSelection: (() -> Void)? = nil
    @State private var availableColumns = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var columnCount: Int { min(state.browserPreferences.pinnedGridColumns ?? 3, availableColumns) }
    private var height: CGFloat {
        guard state.showsPinnedGrid else { return 0 }
        let count = state.sidebarGridPinnedTabs.count
        return count == 0 ? 10 : min(220, CGFloat((count + columnCount - 1) / columnCount) * 50 - 4)
    }

    var body: some View {
        VStack(spacing: 0) {
            if state.showsPinnedGrid && !state.sidebarGridPinnedTabs.isEmpty {
                SidebarScrollView(chrome: chrome) {
                    PinnedTabsGrid(state: state, chrome: chrome, commands: commands,
                                   onSelection: onSelection, columnCount: columnCount)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .openTabDrop(state: state, chrome: chrome) { id, _ in
                            withAnimation(reduceMotion ? nil : .ikagoQuick) { state.movePin(id, intoGrid: true) }
                        }
                        .padding(.vertical, 2)
                        .contextMenu {
                            Picker("Grid size", selection: Binding(
                                get: { state.browserPreferences.pinnedGridColumns ?? 3 },
                                set: { state.browserPreferences.pinnedGridColumns = $0 }
                            )) {
                                ForEach(2...8, id: \.self) { count in Text("\(count) columns").tag(count) }
                            }
                        }
                }.transition(.opacity)
            } else if state.showsPinnedGrid {
                EmptyEssentialsDropZone(state: state, chrome: chrome)
            }
        }
        .frame(height: height)
        .onGeometryChange(for: Int.self) { max(1, Int($0.size.width / 44)) } action: { availableColumns = $0 }
        .animation(reduceMotion ? nil : .ikagoQuick, value: state.sidebarGridPinnedTabs.map(\.id))
        .recordLayout("sidebar-pin-grid")
    }
}

/// A small permanent lip offers an empty grid target without covering rows or changing list geometry.
struct EmptyEssentialsDropZone: View {
    let state: BrowserState
    let chrome: ChromeModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let shape = Capsule()
        shape.fill(state.palette.selected)
            .overlay(shape.strokeBorder(state.palette.separator, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .frame(height: 10).contentShape(Rectangle())
            .opacity(chrome.draggingTabID == nil ? 0 : 1)
            .openTabDrop(state: state, chrome: chrome) { id, _ in
                withAnimation(reduceMotion ? nil : .ikagoQuick) { state.movePin(id, intoGrid: true) }
            }
            .accessibilityLabel("Add tab to grid")
    }
}

// MARK: - Essentials drop
extension View {
    /// Only live tabs can be moved into tab lists, pins or splits.
    func openTabDrop(state: BrowserState, chrome: ChromeModel, perform: @escaping @MainActor @Sendable (String, CGPoint) -> Void) -> some View {
        onDrop(of: [.ikagoTab], isTargeted: nil) { providers, point in
            guard let provider = providers.first else { return false }
            chrome.endTabDrag()
            TabDrag.load(provider, into: state) { id in if state.tab(id) != nil { perform(id, point) } }
            return true
        }
    }
}
