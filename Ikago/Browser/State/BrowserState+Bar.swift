import AppKit

extension BrowserState {
    /// The Sidebar layout's three states: full, a rail of icons, or hidden (`sidebarVisible`).
    var showsSidebarRail: Bool { tabLayout == .vertical && sidebarVisible && browserPreferences.sidebarCompact == true }
    /// The rail's width: room for the traffic lights side by side, and a 36 pt tile.
    static let sidebarRailWidth: CGFloat = 64

    var pageCornerRadius: CGFloat { frameInset == 0 || isImmersive ? 0 : 12 }
    /// Floating island mode: the page fills the window and one pill floats over it, holding the
    /// traffic lights, buttons and tabs. Height is adjustable within a narrower range; the gap doesn't apply.
    var barFloating: Bool { tabLayout == .horizontal && barRounded }
    /// The island's height as drawn.
    var barShownHeight: CGFloat { tabLayout == .horizontal ? topToolbarHeight : CGFloat(barHeight) }
    /// The title row the island sits in (traffic lights are centred on it).
    var barRegion: CGFloat { tabLayout == .horizontal ? topToolbarHeight + (barFloating ? Self.topBarFloatingMargin * 2 : 0) : max(38, barShownHeight + 6) }
    /// A big gap (over 15 pt) joins the title row: the island is centred in row plus gap.
    var barCentersInGap: Bool { !barFloating && barGap > 15 }
    /// Title row height including a gap large enough to centre the island in.
    var barArea: CGFloat { barRegion + (barCentersInGap ? CGFloat(barGap) : 0) }
    /// What is left of the gap to put above the page.
    var barPageGap: CGFloat { tabLayout == .horizontal ? (barFloating ? frameInset : 0) : CGFloat(barGap) }
    /// Island top inset: level with the traffic lights, or centred when the gap is large.
    var barTopInset: CGFloat {
        if tabLayout == .horizontal { return barFloating ? Self.topBarFloatingMargin : 0 }
        let h = barShownHeight
        if barFloating { return 8 }
        return barCentersInGap ? max(3, (barArea - h) / 2) : max(3, 19 - h / 2)
    }

    /// Floating island: how far the page content starts below the card's top edge. The page still
    /// scrolls under the island, and fixed navbars sit below it.
    var floatingContentInset: CGFloat {
        tabLayout == .horizontal && barFloating && !isImmersive ? max(0, topBarChromeHeight - CGFloat(frameInset)) : 0
    }

    /// Space identity colors the whole chrome. A page theme can contribute a subtle tint.
    var barTint: NSColor? {
        if tabLayout == .horizontal { return topBarChromeTint }
        guard tabLayout.usesTopTabs, !barFloating else { return nil }
        let base = palette.nsTint
        guard tintBarWithPage, let tab = activeTab, InternalPage(url: tab.url) == nil,
              let page = tab.themeColor else { return base }
        return base.blended(withFraction: 0.22, of: page) ?? base
    }

    /// Colors for controls drawn on the top bar: the Space's palette, or one that reads on the page color.
    var barPalette: Palette {
        if tabLayout == .horizontal { return topBarPalette }
        return barTint.map { Palette(palette, over: $0) } ?? palette
    }
}
