import SwiftUI

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
            .travellingWithDrag(chrome.draggingTabID != nil && chrome.draggingTabID != tab.id && chrome.selectedTabIDs.contains(tab.id)
                                && chrome.selectedTabIDs.contains(chrome.draggingTabID ?? ""))
            .tabDropTarget(tab, axis: .horizontal, state: state, chrome: chrome)
        } else {
            base.tabDropTarget(tab, axis: .horizontal, state: state, chrome: chrome)
        }
    }
}
