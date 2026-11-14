import AppKit

/// The last line of defence for "no Chromium windows": a titled Chromium window that appears
/// anyway is taken off screen. Borderless ones are left alone, because Chromium also draws
/// its menus and bubbles that way, and docked DevTools is borderless too.
@MainActor
enum ChromiumWindowGuard {
    private static var observers: [NSObjectProtocol] = []
    /// The last of Ikago's own windows to be key, which gets the keyboard back from a Chromium window that took it.
    private static weak var lastIkagoKey: NSWindow?

    static func install() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSWindow.didUpdateNotification, object: nil, queue: .main) { note in
            guard let window = note.object as? NSWindow else { return }
            MainActor.assumeIsolated { hideIfChromium(window) }
        })
        // A service page (chrome://extensions for Settings ▸ Extensions, an install) opens in a Chrome browser frame
        // that becomes key for a moment. Hidden, it would keep the keyboard: Ikago's window looked inactive, its
        // hover controls and popovers went away, and typing went nowhere. Give the keyboard straight back.
        observers.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { note in
            guard let window = note.object as? NSWindow else { return }
            MainActor.assumeIsolated {
                if isChromiumWindow(window) {
                    if shouldHide(window) { returnKeyboard(from: window) }
                } else {
                    lastIkagoKey = window
                }
            }
        })
    }

    private static func returnKeyboard(from window: NSWindow) {
        guard let target = lastIkagoKey, target.isVisible, target !== window else { return }
        target.makeKey()
    }

    /// Every window Chromium's views draw descends from NativeWidgetMacNSWindow, including Chrome's own
    /// browser frame (`BrowserNativeWidgetWindow`), whose class name doesn't contain it.
    private static let widgetClass: AnyClass? = NSClassFromString("NativeWidgetMacNSWindow")

    static func isChromiumWindow(_ window: NSWindow) -> Bool {
        if let widgetClass, window.isKind(of: widgetClass) { return true }
        return NSStringFromClass(type(of: window)).contains("NativeWidget")
    }

    /// Chrome's browser frame, which Ikago never shows (a service such as chrome://extensions runs in one).
    static func isBrowserFrame(_ window: NSWindow) -> Bool {
        NSStringFromClass(type(of: window)).contains("BrowserNativeWidgetWindow")
    }

    /// Marks the DevTools window `DevToolsDock` has docked: the one Chromium window Ikago shows.
    static let dockedDevTools = NSUserInterfaceItemIdentifier("app.ikago.docked-devtools")

    /// Titled Chromium windows, Chrome's browser frame and Chromium's borderless Picture in Picture window (a page's own
    /// PiP button; `ChromiumPictureInPicture` shows the video in Ikago's panel instead), except docked DevTools.
    /// Borderless menus and bubbles stay.
    private static func shouldHide(_ window: NSWindow) -> Bool {
        window.identifier != dockedDevTools && isChromiumWindow(window)
            && (window.styleMask.contains(.titled) || isBrowserFrame(window) || window.title == "Picture in Picture")
    }

    private static func hideIfChromium(_ window: NSWindow) {
        guard window.isVisible, shouldHide(window) else { return }
        let wasKey = window.isKeyWindow
        window.alphaValue = 0
        window.orderOut(nil)
        if wasKey { returnKeyboard(from: window) }
    }
}
