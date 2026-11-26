import SwiftUI
import AppKit

// MARK: - Tab interactions
extension View {
    /// Dropping a tab on empty bar space moves it to the end, out of its folder (and split group).
    func stripDrop(state: BrowserState, chrome: ChromeModel) -> some View {
        openTabDrop(state: state, chrome: chrome) { id, _ in
            withAnimation(.ikago) {
                state.separate(id)
                state.move(id, before: nil, pinned: false, folderID: nil)
            }
        }
    }

    /// Click to select, right-click menu, drag to reorder or split.
    @ViewBuilder
    func tabInteractions(_ tab: TabItem, state: BrowserState, chrome: ChromeModel, commands: BrowserCommands?, drags: Bool = true,
                         beforeClose: @escaping () -> Void = { }) -> some View {
        let base = contextMenu { TabContextMenu(tab: tab, state: state, commands: commands) }
            .onMiddleClick { beforeClose(); withAnimation(.ikago) { commands?.closeTab(tab.id) } }
        if drags {
            base.onDrag {
                chrome.beginTabDrag(tab.id)
                return TabDrag.provider(tab.id)
            } preview: {
                TabDragPreview(tab: tab, colors: state.palette, count: chrome.selectedTabIDs.contains(tab.id) ? chrome.selectedTabIDs.count : 1)
            }
            .travellingWithDrag(tab.id, chrome: chrome)
            .tabDropTarget(tab, axis: .horizontal, state: state, chrome: chrome)
        } else {
            base.tabDropTarget(tab, axis: .horizontal, state: state, chrome: chrome)
        }
    }
}

// MARK: - Middle click
extension View {
    /// Middle-click (the wheel button) runs `action`. SwiftUI has no gesture for it.
    func onMiddleClick(_ action: @escaping () -> Void) -> some View {
        overlay(MiddleClickCatcher(action: action))
    }
}

/// Transparent overlay that only takes part in hit-testing for the extra mouse buttons, so
/// clicks, hovers and drags still reach the view underneath.
private struct MiddleClickCatcher: FillingViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> CatcherView { CatcherView() }
    func updateNSView(_ view: CatcherView, context: Context) { view.action = action }

    final class CatcherView: NSView {
        var action: () -> Void = {}

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let type = NSApp.currentEvent?.type, type == .otherMouseDown || type == .otherMouseUp else { return nil }
            return super.hitTest(point)
        }

        override func otherMouseDown(with event: NSEvent) {
            if event.buttonNumber != 2 { super.otherMouseDown(with: event) }
        }

        override func otherMouseUp(with event: NSEvent) {
            if event.buttonNumber == 2 { action() } else { super.otherMouseUp(with: event) }
        }
    }
}
