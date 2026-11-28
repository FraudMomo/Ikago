import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A dragged tab. Its own type (not text), so web pages ignore it and split-view targets
/// and the sidebar can take it.
struct TabDrag: Codable, Transferable {
    let id: String
    /// The other selected tabs travelling with the dragged one (`TabClick`), set when the drag starts.
    @MainActor static var companions: [String] = []
    static var transferRepresentation: some TransferRepresentation { CodableRepresentation(contentType: .ikagoTab) }

    /// Read the actual payload; drag UI state may end before asynchronous delivery finishes. A tab from another window
    /// is brought into `state`'s window first (`BrowserWindows.bring`), so the drop then places it like its own tabs.
    /// `reversed`: placed one by one after the same row, the last tab goes in first so they keep their order.
    static func load(_ provider: NSItemProvider, into state: BrowserState?, reversed: Bool = false,
                     perform: @escaping @MainActor (String) -> Void) {
        provider.loadDataRepresentation(forTypeIdentifier: UTType.ikagoTab.identifier) { data, _ in
            guard let data, let tab = try? JSONDecoder().decode(TabDrag.self, from: data) else { return }
            Task { @MainActor in
                let ids = travelling(with: tab.id)
                for id in reversed ? ids.reversed() : ids {
                    if let state { BrowserWindows.bring(id, into: state) }
                    perform(id)
                }
            }
        }
    }

    /// The dragged tab and the selected tabs travelling with it, in their sidebar order; the drop takes them all.
    @MainActor static func travelling(with id: String) -> [String] {
        let order = BrowserWindows.owner(of: id)?.state.navigationOrder.map(\.id) ?? []
        let others = companions.filter { $0 != id }
            .sorted { (order.firstIndex(of: $0) ?? .max) < (order.firstIndex(of: $1) ?? .max) }
        companions = []
        return [id] + others
    }

    /// Item provider carrying only this type (no text or file fallbacks a web view would grab).
    static func provider(_ id: String) -> NSItemProvider {
        let provider = NSItemProvider()
        let data = (try? JSONEncoder().encode(TabDrag(id: id))) ?? Data()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.ikagoTab.identifier, visibility: .ownProcess) { done in
            done(data, nil)
            return nil
        }
        return provider
    }
}

extension UTType {
    static let ikagoTab = UTType(exportedAs: "app.ikago.tab")
}

extension TabItem {
    /// A group whose tabs are all closed or asleep (and none of them is on screen).
    static func allAsleep(_ tabs: [TabItem], activeID: String?) -> Bool {
        !tabs.isEmpty && tabs.allSatisfy { $0.isUnloaded && $0.id != activeID }
    }
}

/// What follows the pointer while dragging tabs: the tab, and with several selected, a stack of cards behind it and a
/// badge with how many are moving.
struct TabDragPreview: View {
    let tab: TabItem
    let colors: Palette
    var count = 1

    var body: some View {
        let card = colors.isDark ? Color(white: 0.2) : .white
        let shape = RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
        HStack(spacing: 8) {
            FaviconView(tab: tab)
            Text(tab.displayTitle).lineLimit(1).font(.system(size: 13, weight: .medium))
        }
        .padding(.horizontal, 12).frame(width: 190, height: 32, alignment: .leading)
        // Plain fills: drag previews are rendered offscreen, where Liquid Glass can't draw.
        .background(shape.fill(card).overlay(shape.strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)))
        .background {
            ForEach(Array((1..<min(count, 3)).reversed()), id: \.self) { depth in
                shape.fill(card.opacity(0.85)).overlay(shape.strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5))
                    .offset(x: CGFloat(depth) * 4, y: CGFloat(depth) * 4)
            }
        }
        .overlay(alignment: .topTrailing) {
            if count > 1 {
                Text("\(count)").font(.system(size: 11, weight: .bold).monospacedDigit()).foregroundStyle(.white)
                    .padding(.horizontal, 6).frame(minWidth: 20, minHeight: 20)
                    .background(Capsule().fill(colors.accent))
                    .offset(x: 8, y: -8)
            }
        }
        .padding(10)
        .opacity(0.9)
    }
}

extension View {
    /// A selected tab travelling with the one being dragged: it fades and tucks in, as if stacked under the pointer.
    /// A selected tab carried along by a drag of another selected tab fades and shrinks a little. It reads the drag in
    /// its own view, so a drag starting or ending never rebuilds the rows themselves.
    func travellingWithDrag(_ tabID: String, chrome: ChromeModel) -> some View {
        modifier(TravellingWithDrag(tabID: tabID, chrome: chrome))
    }
}

private struct TravellingWithDrag: ViewModifier {
    let tabID: String
    let chrome: ChromeModel

    func body(content: Content) -> some View {
        let dragged = chrome.draggingTabID
        let travelling = dragged != nil && dragged != tabID && chrome.selectedTabIDs.contains(tabID)
            && chrome.selectedTabIDs.contains(dragged ?? "")
        content
            .opacity(travelling ? 0.35 : 1)
            .scaleEffect(travelling ? 0.96 : 1)
            .animation(.ikago, value: travelling)
    }
}
