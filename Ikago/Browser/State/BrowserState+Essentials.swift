import Foundation

extension BrowserState {
    var showsPinnedGrid: Bool { browserPreferences.showPinnedGrid ?? true }
    var presentsSidebarPinGrid: Bool { showsPinnedGrid }
    var sidebarGridPinnedTabs: [TabItem] {
        pinnedTabs.filter { !$0.pinAsRow && splitGroup(of: $0.id) == nil }
    }

    /// Address-bar navigation preserves live pins. Page links remain native navigation.
    func addressNeedsNewTab(for url: String) -> Bool {
        guard let active = activeTab, active.pinned else { return false }
        return Self.pageKey(active.url) != Self.pageKey(url)
    }
}
