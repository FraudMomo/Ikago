import SwiftUI
import UniformTypeIdentifiers

/// While a tab (or a split pane's header) is dragged over the page: the page is cut along its
/// diagonals into left, right, top and bottom. The zone under the pointer previews the split
/// that dropping would make, with the moved or new pane highlighted. A full group (4) says so.
struct SplitDropOverlay: View {
    let state: BrowserState
    let chrome: ChromeModel
    @State private var edge: SplitEdge?

    private static let edges: [SplitEdge] = [.left, .right, .top, .bottom]
    private var groupCount: Int { state.activeTabID.flatMap { state.splitGroup(of: $0)?.count } ?? 1 }
    /// Dragging a pane that is already in the active group: it moves instead of being added.
    private var isMove: Bool {
        guard let id = chrome.draggingTabID, let active = state.activeTabID else { return false }
        return state.splitGroup(of: active)?.contains(id) == true
    }
    private var hasEmpty: Bool {
        guard let active = state.activeTabID else { return false }
        return state.splitGroup(of: active)?.contains { state.tab($0)?.url == InternalPage.splitEmpty.url } == true
    }
    private var isFull: Bool { !isMove && !hasEmpty && groupCount >= 4 }

    var body: some View {
        let colors = state.palette
        GeometryReader { geo in
            ZStack {
                SplitDropTarget(active: chrome.draggingTabID != nil, accepts: { id in
                    guard let tab = state.tab(id), tab.spaceID == state.activeSpaceID else { return false }
                    let moving = state.activeTabID.flatMap { state.splitGroup(of: $0)?.contains(id) } == true
                    return moving || hasEmpty || groupCount < 4
                }, onEdge: { edge = $0 }, onDrop: { id, zone in
                    chrome.endTabDrag()
                    withAnimation(.ikago) { state.splitWithDropped(id, edge: zone) }
                })
                if chrome.draggingTabID != nil {
                    ForEach(Self.edges, id: \.self) { zone in hint(zone, colors: colors) }
                }
                if chrome.draggingTabID != nil {
                    if let edge { preview(edge, size: geo.size, colors: colors) }
                    else if isFull { preview(.right, size: geo.size, colors: colors) }
                }
            }
        }
        .padding(6)
        .animation(.ikagoQuick, value: edge)
    }

    /// A small bar at each edge: "drop here".
    private func hint(_ zone: SplitEdge, colors: Palette) -> some View {
        let horizontal = zone.isHorizontalAxis
        return Capsule().fill(colors.accent.opacity(edge == nil ? 0.55 : 0.2))
            .frame(width: horizontal ? 4 : 56, height: horizontal ? 56 : 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment(zone))
            .padding(8)
            .allowsHitTesting(false)
    }

    private func alignment(_ zone: SplitEdge) -> Alignment {
        switch zone { case .left: .leading; case .right: .trailing; case .top: .top; case .bottom: .bottom }
    }

    /// The panes after the drop: current ones faint, the new or moved one in the accent color.
    private func preview(_ zone: SplitEdge, size: CGSize, colors: Palette) -> some View {
        let others = isMove ? groupCount - 1 : groupCount
        let layout = BrowserState.layout(afterDropOn: zone, count: others, current: state.splitLayout)
        let count = others + 1
        let rects = isFull ? [] : layout.rects(count: count, in: size)
        let newIndex = zone.isLeading ? 0 : count - 1
        return ZStack(alignment: .topLeading) {
            ForEach(Array(rects.enumerated()), id: \.offset) { index, rect in
                let isNew = index == newIndex
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isNew ? colors.accent.opacity(0.22) : Color.primary.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(isNew ? colors.accent.opacity(0.8) : Color.primary.opacity(0.12), lineWidth: isNew ? 2 : 1))
                    .overlay {
                        if isNew { Image(systemName: isMove ? "arrow.up.left.and.arrow.down.right" : "plus")
                            .font(.system(size: 18, weight: .semibold)).foregroundStyle(colors.accent) }
                    }
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
            }
            if isFull {
                Label("Split view is full (4 tabs)", systemImage: "rectangle.split.2x2")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .surface(Capsule(), colors)
                    .frame(width: size.width, height: size.height)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .transition(.opacity)
    }
}

