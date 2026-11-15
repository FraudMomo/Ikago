import AppKit
import SwiftUI

/// Clicking a tab in the sidebar, the rail or the tab row, as in Finder and Chrome: Shift selects every tab from the
/// last one clicked to this one, ⌘ adds or removes one, ⌥ peeks, a plain click opens the tab and ends the selection.
/// Selected tabs act together: their menu moves, groups or closes them all, and dragging one carries the rest
/// (`TabDrag.companions`).
@MainActor
enum TabClick {
    static func handle(_ tab: TabItem, state: BrowserState, chrome: ChromeModel, commands: BrowserCommands?, open: () -> Void) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.option) { commands?.peekTab(tab.id); return }
        if flags.contains(.shift) {
            let order = state.navigationOrder.map(\.id)
            let anchor = chrome.selectionAnchor.flatMap { order.contains($0) ? $0 : nil } ?? state.activeTabID ?? tab.id
            if let a = order.firstIndex(of: anchor), let b = order.firstIndex(of: tab.id) {
                chrome.selectedTabIDs = Set(order[min(a, b)...max(a, b)])
            } else {
                chrome.selectedTabIDs = [anchor, tab.id]
            }
            chrome.selectionAnchor = anchor
            return
        }
        if flags.contains(.command) {
            if chrome.selectedTabIDs.isEmpty, let active = state.activeTabID { chrome.selectedTabIDs = [active] }
            if chrome.selectedTabIDs.remove(tab.id) == nil { chrome.selectedTabIDs.insert(tab.id) }
            chrome.selectionAnchor = tab.id
            return
        }
        chrome.selectedTabIDs = []
        chrome.selectionAnchor = tab.id
        open()
    }

    /// The selected tabs, in the sidebar's order, when `id` is one of several; otherwise just `id`.
    static func group(including id: String, state: BrowserState, chrome: ChromeModel) -> [String] {
        let selected = chrome.selectedTabIDs.filter { state.tab($0) != nil }
        guard selected.count > 1, selected.contains(id) else { return [id] }
        let order = state.navigationOrder.map(\.id)
        return selected.sorted { (order.firstIndex(of: $0) ?? .max) < (order.firstIndex(of: $1) ?? .max) }
    }
}

extension View {
    /// The tint a selected tab wears (`ChromeModel.selectedTabIDs`).
    func tabSelectionTint(_ selected: Bool, colors: Palette, radius: CGFloat = Radius.row) -> some View {
        background {
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            shape.fill(colors.accent.opacity(0.16))
                .overlay(shape.strokeBorder(colors.accent.opacity(0.45), lineWidth: 1))
                .opacity(selected ? 1 : 0)
                .scaleEffect(selected ? 1 : 0.97)
                .animation(.ikagoQuick, value: selected)
                .allowsHitTesting(false)
        }
    }
}
