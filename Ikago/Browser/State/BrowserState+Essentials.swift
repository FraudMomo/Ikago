import Foundation

extension BrowserState {
    var showsTopBarEssentials: Bool {
        get { browserPreferences.showTopBarEssentials ?? true }
        set { browserPreferences.showTopBarEssentials = newValue }
    }
    var showsTopBarPins: Bool {
        get { browserPreferences.showTopBarPins ?? true }
        set { browserPreferences.showTopBarPins = newValue }
    }
    var topBarShelfPins: [TabItem] { pinnedTabs.filter { splitGroup(of: $0.id) == nil } }
    var showsPinnedGrid: Bool { browserPreferences.showPinnedGrid ?? true }
    var presentsSidebarPinGrid: Bool { tabLayout == .vertical && showsPinnedGrid }

    /// Rows share the top bar's surface and touch, without inter-row padding.
    var topBarAccessoryHeight: CGFloat {
        showsBookmarksBar ? 32 : 0
    }

    /// Address-bar navigation preserves live pins. Page links remain native navigation.
    func addressNeedsNewTab(for url: String) -> Bool {
        guard let active = activeTab, active.pinned else { return false }
        return Self.pageKey(active.url) != Self.pageKey(url)
    }

    var topBarChromeHeight: CGFloat {
        if tabLayout == .horizontal { return topBarHeaderHeight }
        return barArea
    }
}
