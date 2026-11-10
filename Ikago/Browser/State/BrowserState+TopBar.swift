import AppKit

extension BrowserState {
    var topTabStyle: TopTabStyle {
        get { browserPreferences.topTabStyle.flatMap(TopTabStyle.init(rawValue:)) ?? .separate }
        set { browserPreferences.topTabStyle = newValue.rawValue }
    }
    var topBarShowsPageColor: Bool {
        get { browserPreferences.topBarShowPageColor ?? false }
        set { browserPreferences.topBarShowPageColor = newValue }
    }
    var topBarAlwaysShowsTabBar: Bool {
        get { browserPreferences.topBarAlwaysShowTabBar ?? false }
        set { browserPreferences.topBarAlwaysShowTabBar = newValue }
    }
    var topBarShowsTabStrip: Bool {
        topTabStyle == .separate && (topBarAlwaysShowsTabBar || !spaceFolders.isEmpty
            || regularTabs.count + (showsTopBarEssentials && showsTopBarPins ? pinnedTabs.count : 0) > 1)
    }
    static let topToolbarHeights: ClosedRange<Double> = 40...64
    static let topTabBarHeights: ClosedRange<Double> = 28...48
    static let defaultTopToolbarHeight: Double = 52
    static let defaultTopTabBarHeight: Double = 40
    /// Adjustable in both tab styles (Settings ▸ Appearance); Compact tabs live in this row.
    var topToolbarHeight: CGFloat {
        CGFloat(min(Self.topToolbarHeights.upperBound, max(Self.topToolbarHeights.lowerBound,
            browserPreferences.topToolbarHeight ?? Self.defaultTopToolbarHeight)).rounded())
    }
    var topTabBarHeight: CGFloat {
        CGFloat(min(Self.topTabBarHeights.upperBound, max(Self.topTabBarHeights.lowerBound,
            browserPreferences.topTabBarHeight ?? Self.defaultTopTabBarHeight)).rounded())
    }
    /// Tabs and control capsules inside a row of `rowHeight`.
    static func topBarControlHeight(in rowHeight: CGFloat) -> CGFloat { max(24, min(36, rowHeight - 16)) }
    /// Floating mode detaches the bar from the window edges by this margin on every side.
    static let topBarFloatingMargin: CGFloat = 8
    /// Address editing is an opaque native field, independent of the toolbar's glass setting.
    var topBarAddressColor: NSColor { NSColor(hex: isDark ? 0x3A3A3C : 0xFFFFFF) }
    var topTabStripHeight: CGFloat { topBarShowsTabStrip ? topTabBarHeight : 0 }
    var topBarHeaderHeight: CGFloat {
        topToolbarHeight + topTabStripHeight + (showsBookmarksBar ? 32 : 0) + (barFloating ? Self.topBarFloatingMargin * 2 : 0)
    }
    /// The neutral native chrome carries a restrained Space tint, never illegible page ink.
    var topBarChromeTint: NSColor {
        let neutral = NSColor(hex: isDark ? 0x29292C : 0xECECEF)
        var color = neutral.blended(withFraction: 0.16, of: palette.nsTint) ?? neutral
        if topBarShowsPageColor, let tab = activeTab, InternalPage(url: tab.url) == nil, let theme = tab.themeColor {
            color = color.blended(withFraction: 0.06, of: theme) ?? color
        }
        return color
    }
    var topBarPalette: Palette {
        let base = Palette(colors: activeSpace.resolvedColors, isDark: isDark,
                           glass: useGlass && !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)
        return Palette(base, over: topBarChromeTint, panelIsSurface: true)
    }
}
