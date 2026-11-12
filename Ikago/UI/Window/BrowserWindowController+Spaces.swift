import AppKit

extension BrowserWindowController {
    func setSpaceShared(_ id: UUID, shared: Bool) {
        guard let index = state.spaces.firstIndex(where: { $0.id == id }), state.spaces[index].isolated != !shared else { return }
        let active = state.activeTabID.flatMap(state.tab)?.spaceID == id ? state.activeTabID : nil
        if active != nil { state.activeTabID = nil }
        let ids = state.tabs.filter { $0.spaceID == id }.map(\.id)
        for tabID in ids { content.controller(for: tabID)?.hibernate() }
        state.spaces[index].isolated = !shared
        if let active { state.activeTabID = active }
        state.scheduleSave()
    }
}
