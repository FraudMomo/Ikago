import AppKit

/// The last line of defence for "no Chromium windows": a titled Chromium window that appears
/// anyway is taken off screen. Borderless ones are left alone, because Chromium also draws
/// its menus and bubbles that way, and docked DevTools is borderless too.
@MainActor
enum ChromiumWindowGuard {
    private static var observer: NSObjectProtocol?

    static func install() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: NSWindow.didUpdateNotification, object: nil, queue: .main) { note in
            guard let window = note.object as? NSWindow else { return }
            MainActor.assumeIsolated { hideIfChromium(window) }
        }
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

    private static func hideIfChromium(_ window: NSWindow) {
        guard window.isVisible, window.identifier != dockedDevTools, isChromiumWindow(window), window.styleMask.contains(.titled) || isBrowserFrame(window) else { return }
        window.alphaValue = 0
        window.orderOut(nil)
    }
}
