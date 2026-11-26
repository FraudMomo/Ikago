import AppKit

extension BrowserWindowController {
    /// Collapsed sidebar: no traffic lights over the page until the sidebar peeks in (or the Top Tabs row holds
    /// them). Full screen: only with the revealed sidebar.
    var showsTrafficLights: Bool {
        if state.webApp != nil { return !state.isImmersive }
        if state.isImmersive { return chrome.peeking || state.sidebarVisible }
        return state.sidebarVisible || chrome.peeking || state.showsSidebarTopTabs
    }

    /// The icon rail stacks the lights in a column, which the titlebar has no room for.
    /// Not under the Top Tabs row, which holds the lights itself.
    private var railLights: Bool {
        state.webApp == nil && state.showsSidebarRail && !state.showsSidebarTopTabs && (!state.sidebarOnRight || state.sidebarLightsFollow)
    }

    /// The system's buttons in a window; Ikago's own (`FullScreenWindowControls`) in full screen and on the
    /// rail. Convert both axes through the content view: a standard button's titlebar container has its own
    /// origin, which must not be added to the intended window coordinates.
    func positionTrafficLights() {
        guard let window, let content = window.contentView else { return }
        let drawn = window.isInFullScreen || railLights
        for kind: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(kind)?.isHidden = drawn
        }
        let followsRight = state.sidebarOnRight && state.sidebarLightsFollow
        // The same distance from the sidebar's leading edge as on the left (19 pt from the window, the sidebar at the inset).
        let rightInset = content.bounds.width - CGFloat(state.sidebarWidth) + 19 - 2 * CGFloat(state.isImmersive ? 0 : state.frameInset)
        if drawn {
            fullScreenControls.show(above: background.shell)
            let band = browserWindow?.fullScreenTopBand ?? 0
            // Full screen: below what the band leaves of the menu bar, so the menu bar never covers them; no margins.
            let lower = state.immersiveChromeTop
            let inset = state.isImmersive ? 0 : CGFloat(state.frameInset)
            if railLights {
                // A column in the rail; a row in the top row of Expand's full sidebar while it is out over the rail, as
                // when the sidebar is docked. The lights glide between the two with the panel.
                let columnX = state.sidebarOnRight && state.sidebarLightsFollow
                    ? content.bounds.width - inset - (BrowserState.sidebarRailWidth + 14) / 2 : inset + (BrowserState.sidebarRailWidth - 14) / 2
                fullScreenControls.placeRail(column: (columnX, max(inset, 8) + 16 + lower),
                                             row: (followsRight ? rightInset : 19, state.sidebarRowCenter + lower),
                                             band: band, expanded: chrome.rail.expanded)
                chrome.rail.lightsMoves += 1
            } else {
                // The sidebar's top row: docked from the top edge, or peeking inside its margin.
                let frame = CGFloat(state.frameInset)
                let panel: CGFloat = state.sidebarVisible ? 0 : max(frame, 6)
                fullScreenControls.place(firstX: followsRight ? rightInset : state.sidebarVisible ? 19 : panel + 15,
                                         centerFromTop: panel + max(0, 8 - frame) + 18 + lower, band: band, visible: showsTrafficLights)
            }
            return
        }
        fullScreenControls.hide()
        // Both axes, every time: AppKit never moves the buttons back by itself, so setting only one kept whatever
        // the other had been left at (the lights jumped between layouts).
        let center: CGFloat
        let x: CGFloat
        if state.webApp != nil {
            center = 19; x = 19 + CGFloat(state.frameInset)
        } else if state.showsSidebarTopTabs {
            // At the start of the tab row, whichever side the rail is on.
            center = state.sidebarRowCenter; x = 19
        } else if state.sidebarOnRight && !state.sidebarLightsFollow {
            // In the window's top-left corner: on the Top Tabs row, or in their own small capsule.
            center = state.showsSidebarTopTabs ? state.sidebarRowCenter : 23
            x = state.showsSidebarTopTabs ? 14 : 21
        } else if state.sidebarVisible || state.showsSidebarTopTabs {
            center = state.sidebarRowCenter; x = followsRight ? rightInset : 19
        } else {
            // Revealed over the page: inside the floating card's margin.
            let frame = CGFloat(state.frameInset)
            center = max(frame, 6) + max(0, 8 - frame) + BrowserState.sidebarRowHeight / 2
            x = followsRight ? rightInset : max(frame, 6) + 13
        }
        let centerY = content.isFlipped ? content.bounds.minY + center : content.bounds.maxY - center
        for (index, kind) in ([.closeButton, .miniaturizeButton, .zoomButton] as [NSWindow.ButtonType]).enumerated() {
            guard let button = window.standardWindowButton(kind), let parent = button.superview else { continue }
            let point = parent.convert(NSPoint(x: x + CGFloat(index) * 23, y: centerY), from: content)
            let origin = NSPoint(x: point.x.rounded(), y: (point.y - button.frame.height / 2).rounded())
            if button.frame.origin != origin { button.setFrameOrigin(origin) }
        }
    }
}
