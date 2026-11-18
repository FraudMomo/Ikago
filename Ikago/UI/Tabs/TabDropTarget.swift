import SwiftUI
import UniformTypeIdentifiers

extension View {
    func tabDropTarget(_ tab: TabItem, axis: Axis, state: BrowserState, chrome: ChromeModel) -> some View {
        modifier(TabDropTarget(tab: tab, axis: axis, state: state, chrome: chrome))
    }

    func tabListEndDrop(state: BrowserState, chrome: ChromeModel) -> some View {
        modifier(TabListEndDrop(state: state, chrome: chrome))
    }
}

/// Pure SwiftUI tab rows share SwiftUI's drag lifecycle. Native destinations stay above web pages only.
private struct TabDropTarget: ViewModifier {
    let tab: TabItem
    let axis: Axis
    let state: BrowserState
    let chrome: ChromeModel
    @State private var insertionAfter: Bool?
    @State private var length = MeasuredLength()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(isSource ? 0.5 : 1)
            .onGeometryChange(for: CGFloat.self) { axis == .horizontal ? $0.size.width : $0.size.height } action: { length.value = $0 }
            .onDrop(of: [.ikagoTab], delegate: TabReorderDropDelegate(
                axis: axis, length: length, preview: $insertionAfter,
                accepts: { state.canReorderTab($0, relativeTo: tab.id) },
                sourceID: chrome.draggingTabID, perform: { id, after in
                    withAnimation(animation) { _ = state.reorderTab(id, relativeTo: tab.id, after: after) }
                    chrome.endTabDrag()
                }, into: state))
            .overlay(alignment: alignment) {
                if insertionAfter != nil { TabInsertionIndicator(horizontal: axis == .horizontal) }
            }
            .onChange(of: chrome.draggingTabID) { _, id in if id == nil { insertionAfter = nil } }
    }

    private var animation: Animation? { reduceMotion ? nil : .ikagoQuick }
    private var isSource: Bool {
        guard let id = chrome.draggingTabID else { return false }
        return id == tab.id || state.splitGroup(of: tab.id)?.contains(id) == true
    }
    private var alignment: Alignment {
        axis == .horizontal ? (insertionAfter == true ? .trailing : .leading) : (insertionAfter == true ? .bottom : .top)
    }
}

private struct TabListEndDrop: ViewModifier {
    let state: BrowserState
    let chrome: ChromeModel
    @State private var insertionAfter: Bool?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onDrop(of: [.ikagoTab, .ikagoGroup], delegate: ListEndDropDelegate(tabs: TabReorderDropDelegate(
                axis: .vertical, length: MeasuredLength(), preview: $insertionAfter,
                accepts: { state.tab($0)?.spaceID == state.activeSpaceID },
                sourceID: chrome.draggingTabID, perform: { id, _ in
                    withAnimation(reduceMotion ? nil : .ikagoQuick) { _ = state.moveTabToListEnd(id) }
                    chrome.endTabDrag()
                }, into: state), state: state, chrome: chrome, preview: $insertionAfter))
            .overlay(alignment: .top) {
                if insertionAfter != nil { TabInsertionIndicator(horizontal: false) }
            }
            .onChange(of: chrome.draggingTabID) { _, id in if id == nil { insertionAfter = nil } }
            .onChange(of: chrome.draggingFolderID) { _, id in if id == nil { insertionAfter = nil } }
    }
}

/// The end of the list: tabs go last among the loose tabs; a group leaves any group it is in and goes last at the top
/// level.
private struct ListEndDropDelegate: DropDelegate {
    let tabs: TabReorderDropDelegate
    let state: BrowserState
    let chrome: ChromeModel
    @Binding var preview: Bool?

    private func isGroup(_ info: DropInfo) -> Bool { info.hasItemsConforming(to: [.ikagoGroup]) }
    private var groupAccepted: Bool {
        chrome.draggingFolderID.map { id in state.folders.contains { $0.id == id && $0.spaceID == state.activeSpaceID } } ?? false
    }

    func validateDrop(info: DropInfo) -> Bool { isGroup(info) ? groupAccepted : tabs.validateDrop(info: info) }
    func dropEntered(info: DropInfo) {
        if isGroup(info) { preview = groupAccepted ? true : nil } else { tabs.dropEntered(info: info) }
    }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard isGroup(info) else { return tabs.dropUpdated(info: info) }
        preview = groupAccepted ? true : nil
        return DropProposal(operation: groupAccepted ? .move : .cancel)
    }
    func dropExited(info: DropInfo) { preview = nil }
    func performDrop(info: DropInfo) -> Bool {
        guard isGroup(info), let provider = info.itemProviders(for: [.ikagoGroup]).first else { return tabs.performDrop(info: info) }
        preview = nil
        GroupDrag.load(provider) { id in
            chrome.endFolderDrag()
            guard state.folders.contains(where: { $0.id == id && $0.spaceID == state.activeSpaceID }) else { return }
            withAnimation(.ikagoQuick) { state.moveFolder(id, into: nil) }
        }
        return true
    }
}

/// The endpoints remain visible beside the drag image; the band makes the destination easy to follow.
private struct TabInsertionIndicator: View {
    let horizontal: Bool

    var body: some View {
        GeometryReader { geometry in
            let line = Path { path in
                if horizontal {
                    path.move(to: CGPoint(x: 5, y: 5))
                    path.addLine(to: CGPoint(x: 5, y: max(5, geometry.size.height - 5)))
                } else {
                    path.move(to: CGPoint(x: 5, y: 5))
                    path.addLine(to: CGPoint(x: max(5, geometry.size.width - 5), y: 5))
                }
            }
            line.stroke(Color.accentColor.opacity(0.2), style: StrokeStyle(lineWidth: 10, lineCap: .round))
            line.stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            Circle().fill(Color.accentColor).frame(width: 7, height: 7).position(x: 5, y: 5)
            Circle().fill(Color.accentColor).frame(width: 7, height: 7)
                .position(x: horizontal ? 5 : max(5, geometry.size.width - 5),
                          y: horizontal ? max(5, geometry.size.height - 5) : 5)
        }
        .frame(width: horizontal ? 10 : nil, height: horizontal ? nil : 10)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .transaction { $0.animation = nil }
    }
}
