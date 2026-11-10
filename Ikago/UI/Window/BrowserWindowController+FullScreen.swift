import AppKit

/// Ikago's own full screen. macOS's slides a separate titlebar strip over the top of the window whenever the
/// menu bar shows, which covers the sidebar's top row and the top bars. Instead the window grows to cover
/// the display, the Dock and menu bar hide themselves while it is key, and everything starts below the
/// camera housing, a black band where the menu bar appears. The page goes edge to edge (`state.isImmersive`):
/// the sidebar slides in from the left edge and the top bars drop in from the top (`TopBarReveal`), with
/// Ikago's own traffic lights (`FullScreenWindowControls`) in their windowed place.
extension BrowserWindowController {
    var browserWindow: BrowserWindow? { window as? BrowserWindow }

    func toggleIkagoFullScreen() {
        guard let window = browserWindow else { return }
        window.isIkagoFullScreen ? exitIkagoFullScreen() : enterIkagoFullScreen()
    }

    private func enterIkagoFullScreen() {
        guard let window = browserWindow, !window.isIkagoFullScreen, let screen = window.screen ?? NSScreen.main else { return }
        fullScreenControls.measure()
        fullScreenRestore = (window.frame, window.frameAutosaveName)
        window.setFrameAutosaveName("")  // the windowed frame is the one to remember
        window.isIkagoFullScreen = true
        window.styleMask.remove(.resizable)
        // The menu bar's height, read while it still shows: revealed bars and lights go below it.
        let menuBar = screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top : screen.frame.maxY - screen.visibleFrame.maxY
        fullScreenMenuBar = menuBar > 0 ? menuBar : NSStatusBar.system.thickness
        window.fullScreenTopBand = fullScreenBandHeight(on: screen)
        applyFullScreenPresentation()
        chrome.peeking = false
        window.setFrame(screen.frame, display: true, animate: true)
        layoutFullScreenBand()
        state.isImmersive = true
        positionTrafficLights()
        refitChromiumPages()
    }

    func exitIkagoFullScreen() {
        guard let window = browserWindow, window.isIkagoFullScreen else { return }
        NotificationCenter.default.post(name: BrowserWindow.willExitIkagoFullScreen, object: window)
        chrome.peeking = false
        state.isImmersive = false
        state.immersiveChromeTop = 0
        window.isIkagoFullScreen = false
        window.fullScreenTopBand = 0
        applyFullScreenPresentation()
        layoutFullScreenBand()
        window.styleMask.insert(.resizable)
        positionTrafficLights()
        if let restore = fullScreenRestore {
            window.setFrame(restore.frame, display: true, animate: true)
            if !restore.autosave.isEmpty { window.setFrameAutosaveName(restore.autosave) }
        }
        fullScreenRestore = nil
        positionTrafficLights()
        refitChromiumPages()
    }

    /// Chromium pages can keep the size they saw during the window's animation and the sidebar's (cutting off the
    /// page's top); fit them again once both have settled.
    private func refitChromiumPages() {
        for delay in [0.05, 0.45] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                for controller in self.content.controllers.values { (controller.page as? CEFWebTab)?.refitPage() }
            }
        }
    }

    /// The black band above the page: the camera housing's height, unless the person wants the whole display.
    func fullScreenBandHeight(on screen: NSScreen?) -> CGFloat {
        state.browserPreferences.fullScreenUnderNotch == true ? 0 : screen?.safeAreaInsets.top ?? 0
    }

    /// The Dock and menu bar hide only while a full-screen window is key; other windows and apps get them back.
    func applyFullScreenPresentation() {
        guard let window = browserWindow else { return }
        let options: NSApplication.PresentationOptions = window.isIkagoFullScreen && window.isKeyWindow ? [.autoHideDock, .autoHideMenuBar] : []
        if NSApp.presentationOptions != options { NSApp.presentationOptions = options }
    }

    /// The shell starts below the band, which is black like the camera housing it surrounds.
    func layoutFullScreenBand() {
        guard let window = browserWindow, let content = window.contentView, let shell = background.shell else { return }
        let band = window.fullScreenTopBand
        background.shellTopInset = band
        background.layoutSubtreeIfNeeded()
        fullScreenBand.frame = NSRect(x: 0, y: content.bounds.height - band, width: content.bounds.width, height: band)
        fullScreenBand.autoresizingMask = [.width, .minYMargin]
        if band > 0, fullScreenBand.superview == nil { content.addSubview(fullScreenBand, positioned: .above, relativeTo: shell) }
        if band == 0 { fullScreenBand.removeFromSuperview() }
        // What the band leaves of the menu bar would cover the top of revealed bars: they start below it.
        state.immersiveChromeTop = window.isIkagoFullScreen ? max(0, fullScreenMenuBar - band) : 0
        fullScreenBand.wantsLayer = true
        fullScreenBand.layer?.backgroundColor = NSColor.black.cgColor
    }
}
