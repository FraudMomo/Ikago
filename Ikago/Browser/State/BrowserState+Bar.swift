import SwiftUI

extension BrowserState {
    /// Settings ▸ Appearance ▸ Layout ▸ Sidebar + Tabs: tabs and an address bar above the page, and the sidebar only as
    /// a rail of icons or hidden (never the full sidebar).
    var usesTabsLayout: Bool { browserPreferences.sidebarTopTabs == true }
    /// The tab row and address bar are on screen (full screen gives the page the whole display).
    var showsSidebarTopTabs: Bool { usesTabsLayout && !isImmersive }
    /// The address bar under the tab row, part of the page's card.
    static let tabsToolbarHeight: CGFloat = 36
    /// The sidebar's top row (traffic lights and toolbar controls), measured from the window's top edge. Everything
    /// that shares that line, the lights, the sidebar's controls and the Sidebar + Tabs row, centres on `sidebarRowCenter`.
    var sidebarRowTop: CGFloat { max(8, CGFloat(frameInset)) }
    static let sidebarRowHeight: CGFloat = 36
    var sidebarRowCenter: CGFloat { sidebarRowTop + Self.sidebarRowHeight / 2 }
    /// The docked sidebar is part of the window's own surface (no card of its own), so only the page is a rounded card.
    /// Liquid Glass keeps its glass panel, except with the frosted sidebar: then the window itself is the frosted surface
    /// (`WindowBackgroundView`), and a card of its own would stack a second, flatter layer on it.
    var sidebarJoinsWindow: Bool { !useGlass || frostedChrome }
    /// Settings ▸ Appearance ▸ translucent sidebar, unless macOS's Reduce Transparency is on: the window is frosted, and
    /// in Sidebar + Tabs the active tab and the address bar are one lighter, see-through sheet over it.
    var frostedChrome: Bool {
        browserPreferences.translucentSidebar == true && !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }
    /// The active tab and address bar's fill: the page's color, see-through when the window is frosted, so tab and bar
    /// read as one lighter sheet of the frost that settles into the solid page below.
    var tabSheetColor: Color { frostedChrome ? palette.pageBackground.opacity(palette.isDark ? 0.42 : 0.62) : palette.pageBackground }
    var sidebarGroupStyle: SidebarGroupStyle { browserPreferences.sidebarGroupStyle ?? .cards }
    /// The sidebar's three states: full, a rail of icons, or hidden (`sidebarVisible`).
    var showsSidebarRail: Bool { sidebarVisible && (browserPreferences.sidebarCompact == true || usesTabsLayout) }
    /// The rail's width: room for the traffic lights side by side, and a 36 pt tile.
    static let sidebarRailWidth: CGFloat = 64

    var pageCornerRadius: CGFloat { frameInset == 0 || isImmersive ? 0 : Radius.card }
}
