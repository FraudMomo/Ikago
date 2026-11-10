import AppKit

extension BrowserWindowController {
    /// Collapsed sidebar: no traffic lights over the page until the sidebar peeks in.
    /// Full screen: only with the revealed sidebar or top bar.
    var showsTrafficLights: Bool {
        if state.isImmersive { return chrome.peeking || (state.tabLayout == .vertical && state.sidebarVisible) }
        return state.tabLayout.usesTopTabs || state.sidebarVisible || chrome.peeking
    }

    /// The icon rail stacks the lights in a column, which the titlebar has no room for.
    private var railLights: Bool { state.showsSidebarRail }

    /// The system's buttons in a window; Ikago's own (`FullScreenWindowControls`) in full screen and on the
    /// rail. Convert both axes through the content view: a standard button's titlebar container has its own
    /// origin, which must not be added to the intended window coordinates.
    func positionTrafficLights() {
        guard let window, let content = window.contentView else { return }
        let drawn = window.isInFullScreen || railLights
        for kind: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(kind)?.isHidden = drawn
        }
        let topTabs = state.tabLayout.usesTopTabs
        let centerFromTop = state.barTopInset + state.barShownHeight / 2
        let firstX: CGFloat = state.barFloating ? BrowserState.topBarFloatingMargin + 12 : 11
        if drawn {
            fullScreenControls.show()
            let band = browserWindow?.fullScreenTopBand ?? 0
            // Full screen: below what the band leaves of the menu bar, so the menu bar never covers them; no margins.
            let lower = state.immersiveChromeTop
            let inset = state.isImmersive ? 0 : CGFloat(state.frameInset)
            if railLights {
                fullScreenControls.place(firstX: inset + (BrowserState.sidebarRailWidth - 14) / 2,
                                         centerFromTop: max(inset, 8) + 16 + lower, band: band, vertical: true, visible: true)
            } else if topTabs {
                fullScreenControls.place(firstX: firstX, centerFromTop: centerFromTop + lower, band: band, visible: showsTrafficLights)
            } else {
                // The sidebar's top row: docked from the top edge, or peeking inside its margin.
                let frame = CGFloat(state.frameInset)
                let panel: CGFloat = state.sidebarVisible ? 0 : max(frame, 6)
                fullScreenControls.place(firstX: state.sidebarVisible ? 19 : panel + 15,
                                         centerFromTop: panel + max(0, 8 - frame) + 18 + lower, band: band, visible: showsTrafficLights)
            }
            return
        }
        fullScreenControls.hide()
        // Sidebar: AppKit's place, set again in case another layout moved them (AppKit never moves them back by
        // itself). Top bars: centred on the bar.
        let centerY = content.isFlipped ? content.bounds.minY + centerFromTop : content.bounds.maxY - centerFromTop
        for (index, kind) in ([.closeButton, .miniaturizeButton, .zoomButton] as [NSWindow.ButtonType]).enumerated() {
            guard let button = window.standardWindowButton(kind), let parent = button.superview else { continue }
            if topTabs {
                let point = parent.convert(NSPoint(x: firstX + CGFloat(index) * 23, y: centerY), from: content)
                let origin = NSPoint(x: point.x, y: point.y - button.frame.height / 2)
                if button.frame.origin != origin { button.setFrameOrigin(origin) }
            } else {
                let x = parent.convert(NSPoint(x: 19 + CGFloat(index) * 23, y: 0), from: content).x
                if button.frame.origin.x != x { button.setFrameOrigin(NSPoint(x: x, y: button.frame.origin.y)) }
            }
        }
    }
}
