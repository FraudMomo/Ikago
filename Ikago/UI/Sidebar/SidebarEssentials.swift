import SwiftUI
import UniformTypeIdentifiers

// MARK: - Essentials
/// The essentials as one row of the sidebar's list (`SidebarOutline.Row.Kind.essentials`): a band for drops above them,
/// then the grid of pinned tabs. The list takes every drop on the row (`spot(at:width:_:)` says what is under the
/// pointer): views inside a list's row never see drops, the list does. The list must also know a row's height before
/// drawing it, so the height and the grid's columns come from the state and the sidebar's width, never from measuring,
/// and the grid doesn't scroll by itself (the list does).
struct SidebarEssentials: View {
    let state: BrowserState
    let chrome: ChromeModel
    weak var commands: BrowserCommands?
    var onSelection: (() -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The top of the row: a drag over it goes above the essentials. With pins above, it is the space between them and
    /// the grid, the same as the space under the grid (`after`).
    static let band: CGFloat = 16
    /// Under the grid, so the rows after it sit as far from it as the pins above do.
    private static let after: CGFloat = 12
    /// A tile row: 42 pt tiles 8 pt apart, inside 2 pt of padding.
    private static let tileRow: CGFloat = 50

    var body: some View {
        let grid = Self.gridHeight(state)
        VStack(spacing: 0) {
            Color.clear.frame(height: Self.band)
            if state.showsPinnedGrid && !state.sidebarGridPinnedTabs.isEmpty {
                PinnedTabsGrid(state: state, chrome: chrome, commands: commands, onSelection: onSelection, columnCount: Self.columns(state))
                    .padding(.vertical, 2)
                    .frame(height: grid, alignment: .top)
            } else if state.showsPinnedGrid {
                EmptyEssentialsDropZone(state: state, chrome: chrome)
            }
            Spacer(minLength: 0)
        }
        .animation(reduceMotion ? nil : .ikagoQuick, value: state.sidebarGridPinnedTabs.map(\.id))
        .recordLayout("sidebar-pin-grid")
    }

    /// Columns: three or four as chosen, fewer only when the sidebar is too narrow for them.
    static func columns(_ state: BrowserState) -> Int {
        min(state.essentialsColumns, max(1, Int((CGFloat(state.sidebarWidth) - 20) / 44)))
    }

    /// The grid alone: none when hidden, the drop box when empty, else its rows of tiles.
    static func gridHeight(_ state: BrowserState) -> CGFloat {
        guard state.showsPinnedGrid else { return 0 }
        let count = state.sidebarGridPinnedTabs.count
        guard count > 0 else { return EmptyEssentialsDropZone.height }
        return CGFloat((count + columns(state) - 1) / columns(state)) * tileRow
    }

    /// The whole row: the band, the grid and the space after.
    static func height(_ state: BrowserState) -> CGFloat {
        let grid = gridHeight(state)
        return band + grid + (grid > 0 ? after : 0)
    }

    /// What is under a point of the row (from its top-left; `width` is the row's).
    enum Spot: Equatable {
        /// The band: above the essentials.
        case band
        /// The grid: before this tile (nil: after the last).
        case grid(before: String?)
        /// Space under it.
        case after
    }

    /// What is under a point of the list's essentials row (from its top-left; `width` is the row's): the row spans the
    /// sidebar's margins, the essentials sit inside them.
    static func spot(inRow point: CGPoint, width: CGFloat, _ state: BrowserState) -> Spot {
        let margin = SidebarOutlineList.margin
        return spot(at: CGPoint(x: point.x - margin, y: point.y), width: width - 2 * margin, state)
    }

    static func spot(at point: CGPoint, width: CGFloat, _ state: BrowserState) -> Spot {
        guard point.y >= band else { return .band }
        let y = point.y - band
        guard y < gridHeight(state) else { return .after }
        let tabs = state.sidebarGridPinnedTabs
        guard !tabs.isEmpty else { return .grid(before: nil) }
        // Flexible columns 8 pt apart: each column and its gap is (width + 8) / columns wide.
        let count = columns(state)
        let pitch = (width + 8) / CGFloat(count)
        let column = min(count - 1, max(0, Int(point.x / pitch)))
        var index = max(0, Int((y - 2) / tileRow)) * count + column
        // The right half of a tile is after it.
        if point.x - CGFloat(column) * pitch > (pitch - 8) / 2 { index += 1 }
        return .grid(before: index < tabs.count ? tabs[index].id : nil)
    }
}

/// No essentials yet: a box the size of a tile row that says what it is for, brighter while a tab is dragged (the list
/// takes the drop).
struct EmptyEssentialsDropZone: View {
    static let height: CGFloat = 44
    let state: BrowserState
    let chrome: ChromeModel
    var body: some View {
        let colors = state.palette
        let dragging = chrome.draggingTabID != nil
        let shape = RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
        Text(dragging ? "Drop here to add to Essentials" : "Drag tabs here for Essentials")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(dragging ? colors.secondary : colors.tertiary)
            .lineLimit(1).minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity).frame(height: Self.height)
            .background(shape.fill(dragging ? colors.selected : .clear))
            .overlay(shape.strokeBorder(colors.separator, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .animation(.ikagoQuick, value: dragging)
            .accessibilityHidden(true)
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
