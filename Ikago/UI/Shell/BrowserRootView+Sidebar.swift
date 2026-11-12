import SwiftUI

extension BrowserRootView {
    var sidebarLayout: some View {
        HStack(spacing: 0) {
            if state.sidebarOnRight { contentCard(for: .vertical).padding(.leading, inset) }
            if state.sidebarOnRight && docksSidebar { sidebarResize }
            if docksSidebar || sidebarMountedForPlacement {
                sidebarDock
            }
            if !state.sidebarOnRight && docksSidebar { sidebarResize }
            if !state.sidebarOnRight { contentCard(for: .vertical).padding(.leading, docksSidebar ? 0 : inset) }
        }
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
        .clipped()
        .sidebarPanel(state.palette, radius: radius, translucent: state.browserPreferences.translucentSidebar == true)
        .padding(state.sidebarOnRight ? [.trailing, .top, .bottom] : [.leading, .top, .bottom], inset)
        .frame(width: docksSidebar ? sidebarShownWidth + inset : 0, alignment: state.sidebarOnRight ? .leading : .trailing)
        .clipped().allowsHitTesting(docksSidebar)
    }
}
