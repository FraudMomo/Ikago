import SwiftUI

extension BrowserRootView {
    var sidebarLayout: some View {
        HStack(spacing: 0) {
            if state.sidebarOnRight { pageColumn.padding(.leading, inset) }
            if state.sidebarOnRight && docksSidebar { sidebarResize }
            if docksSidebar || sidebarMountedForPlacement {
                sidebarDock
            }
            if !state.sidebarOnRight && docksSidebar { sidebarResize }
            if !state.sidebarOnRight { pageColumn.padding(.leading, docksSidebar ? 0 : inset) }
        }
        // Every margin of the window moves it, the side ones too when the sidebar is hidden (bars and the page are on top).
        .background(WindowDragArea())
    }

    /// The page. In Sidebar + Tabs the tab row (`SidebarTopTabs`) and the address bar (`TabsToolbar`) sit above it, each
    /// in its own host like the sidebar; the address bar is the top of the page's card, and the active tab arches into
    /// it, so tab, address and page read as one sheet. One content card either way, so switching never moves the page
    /// between hosts.
    private var pageColumn: some View {
        let trailing = inset + (chrome.showPageAssistant && state.browserPreferences.pageIntelligence == true ? PageAssistantView.width : 0)
        return VStack(spacing: 0) {
            if state.showsSidebarTopTabs {
                IsolatedHost(chrome: chrome) {
                    SidebarTopTabs(state: state, chrome: chrome, commands: commands, leadingReserve: tabRowLeadingReserve)
                }
                .frame(height: SidebarTopTabs.height(state))
                .padding(.trailing, trailing)
                .transition(.opacity.combined(with: .offset(y: -8)))
                IsolatedHost(chrome: chrome) {
                    TabsToolbar(state: state, chrome: chrome, palette: palette, commands: commands)
                }
                .frame(height: state.tabsToolbarHeight)
                .background {
                    UnevenRoundedRectangle(topLeadingRadius: state.pageCornerRadius, topTrailingRadius: state.pageCornerRadius,
                                           style: .continuous)
                        .fill(state.tabSheetColor)
                }
                // No rule under it: tab, address and page are one sheet in one color, so the active tab's arch runs
                // straight down into the page.
                .padding(.trailing, trailing)
                .transition(.opacity)
            }
            contentCard
        }
    }

    /// Room at the tab row's start for the traffic lights, which end 79 pt into the window. The same tabs position
    /// with the rail shown or hidden, so the row doesn't shift when the rail comes and goes.
    private var tabRowLeadingReserve: CGFloat {
        let column = docksSidebar && !state.sidebarOnRight ? inset + BrowserState.sidebarRailWidth + CGFloat(state.sidebarGap) : inset
        return max(0, 87 - column)
    }

    @ViewBuilder private var sidebarResize: some View {
        if state.showsSidebarRail { Color.clear.frame(width: state.sidebarGap) }
        else { SidebarResizeHandle(state: state, width: state.sidebarGap) }
    }

    private var sidebarDock: some View {
        Group {
            if state.showsSidebarRail { SidebarRail(state: state, commands: commands).transition(.opacity) }
            else {
                IsolatedHost(chrome: chrome) { SidebarView(state: state, chrome: chrome, palette: palette, commands: commands) }
                    .frame(width: state.sidebarWidth).transition(.opacity)
            }
        }
        .frame(width: sidebarShownWidth, alignment: .leading)
        .padding(.top, state.isImmersive ? state.immersiveChromeTop : 0)
        // Sidebar + Tabs: the rail starts under the tab row, level with the address bar.
        .padding(.top, state.showsSidebarTopTabs ? SidebarTopTabs.height(state) - inset : 0)
        .clipped()
        // Joined to the window (glass off), the sidebar draws nothing of its own: it and the tab row above the page are
        // one surface, the window's, and only the page is a card. With glass on it keeps its glass panel.
        .modifier(SidebarDockSurface(state: state, radius: radius))
        .padding(state.sidebarOnRight ? [.trailing, .top, .bottom] : [.leading, .top, .bottom], inset)
        .frame(width: docksSidebar ? sidebarShownWidth + inset : 0, alignment: state.sidebarOnRight ? .leading : .trailing)
        .clipped().allowsHitTesting(docksSidebar)
    }
}

private struct SidebarDockSurface: ViewModifier {
    let state: BrowserState
    let radius: CGFloat
    func body(content: Content) -> some View {
        if state.sidebarJoinsWindow { content }
        else { content.sidebarPanel(state.palette, radius: radius, translucent: state.browserPreferences.translucentSidebar == true) }
    }
}
