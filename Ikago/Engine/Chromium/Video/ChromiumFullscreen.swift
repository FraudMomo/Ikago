import AppKit
import IKCEFBridge

/// Element fullscreen on Chromium (a video's fullscreen button on YouTube). WebKit does this by itself;
/// CEF only reports it. The page view moves above Ikago's own interface, fills the window below the camera
/// housing, and the window goes full screen; leaving puts everything back as it was. Leaving the window's full screen
/// (the green button, Mission Control) also ends the page's.
@MainActor
final class ChromiumFullscreen {
    private weak var page: IKCEFPage?
    private var saved: (superview: NSView, frame: NSRect, mask: NSView.AutoresizingMask, inset: CGFloat, above: NSView?)?
    private var tookWindowFullScreen = false
    private var observer: NSObjectProtocol?
    private var resizeObserver: NSObjectProtocol?
    private(set) var isActive = false

    init(page: IKCEFPage) { self.page = page }

    func pageChanged(fullscreen: Bool) {
        fullscreen ? enter() : leave()
    }

    private func enter() {
        guard !isActive, let page, let window = page.window, let content = window.contentView,
              let superview = page.superview else { return }
        isActive = true
        let index = superview.subviews.firstIndex(of: page)
        let above = index.flatMap { $0 + 1 < superview.subviews.count ? superview.subviews[$0 + 1] : nil }
        saved = (superview, page.frame, page.autoresizingMask, page.topInset, above)
        page.removeFromSuperview()
        page.topInset = 0
        // Below the camera housing in Ikago's full screen, like the bars.
        let band = (window as? BrowserWindow)?.fullScreenTopBand ?? 0
        page.frame = NSRect(x: 0, y: 0, width: content.bounds.width, height: content.bounds.height - band)
        page.autoresizingMask = [.width, .height]
        content.addSubview(page, positioned: .above, relativeTo: nil)
        window.makeFirstResponder(page)
        tookWindowFullScreen = !window.isInFullScreen
        if tookWindowFullScreen {
            window.toggleFullScreen(nil)
            // The window's frame and band changed: fill it below the band.
            let band = (window as? BrowserWindow)?.fullScreenTopBand ?? 0
            page.frame = NSRect(x: 0, y: 0, width: content.bounds.width, height: content.bounds.height - band)
        }
        resizeObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.fitFullscreenPage() }
        }
        fitFullscreenPage()
        let exitName = window is BrowserWindow ? BrowserWindow.willExitIkagoFullScreen : NSWindow.willExitFullScreenNotification
        observer = NotificationCenter.default.addObserver(forName: exitName, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isActive else { return }
                self.tookWindowFullScreen = false  // already leaving
                self.page?.exitFullscreen()
            }
        }
    }

    private func fitFullscreenPage() {
        guard isActive, let page, let window = page.window, let content = window.contentView else { return }
        let band = (window as? BrowserWindow)?.fullScreenTopBand ?? 0
        page.topInset = 0
        page.frame = NSRect(x: 0, y: 0, width: content.bounds.width, height: max(0, content.bounds.height - band))
        page.needsLayout = true
        page.layoutSubtreeIfNeeded()
    }

    private func leave() {
        guard isActive, let page else { return }
        isActive = false
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        if let resizeObserver { NotificationCenter.default.removeObserver(resizeObserver) }
        resizeObserver = nil
        let window = page.window
        if let saved {
            page.removeFromSuperview()
            if let above = saved.above, above.superview === saved.superview {
                saved.superview.addSubview(page, positioned: .below, relativeTo: above)
            } else {
                saved.superview.addSubview(page)
            }
            // The window changed size meanwhile: fill the tab's area as it is now, or the page keeps the old size
            // and leaves a gap.
            page.autoresizingMask = saved.mask.isEmpty ? [.width, .height] : saved.mask
            page.frame = saved.superview.bounds
            page.topInset = saved.inset
        }
        saved = nil
        if tookWindowFullScreen, let window, window.isInFullScreen { window.toggleFullScreen(nil) }
        tookWindowFullScreen = false
    }

    /// The tab is closing: give the window back first.
    func tearDown() {
        if isActive { leave() }
    }
}
