import AppKit
import WebKit
import IKCEFBridge

/// Reject page focus before NSWindow resigns the address editor. A WKWebView responder
/// override alone runs too late: refusing there can already leave the window without an editor.
@MainActor
final class BrowserWindow: NSWindow {
    var protectsAddressFocus: @MainActor () -> Bool = { false }
    var dismissAddress: @MainActor () -> Void = {}
    private var closing = false
    /// Ikago's own full screen (`IkagoFullScreen`) instead of macOS's, which slides its titlebar over the bars.
    var fullScreenHandler: (@MainActor () -> Void)?
    /// In Ikago's full screen: the window covers the display and the frame isn't kept below the menu bar.
    var isIkagoFullScreen = false
    /// Height of the band the bars leave above them in Ikago's full screen (the camera housing).
    var fullScreenTopBand: CGFloat = 0
    static let willExitIkagoFullScreen = Notification.Name("app.ikago.willExitFullScreen")

    override func toggleFullScreen(_ sender: Any?) {
        if let fullScreenHandler { fullScreenHandler() } else { super.toggleFullScreen(sender) }
    }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        isIkagoFullScreen ? frameRect : super.constrainFrameRect(frameRect, to: screen)
    }

    override func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(toggleFullScreen(_:)), fullScreenHandler != nil {
            item.title = isIkagoFullScreen ? "Exit Full Screen" : "Enter Full Screen"
            return true
        }
        return super.validateMenuItem(item)
    }

    override func sendEvent(_ event: NSEvent) {
        if [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type),
           protectsAddressFocus(), let root = contentView,
           !AddressRegionView.contains(event.locationInWindow, in: root) {
            dismissAddress()
        }
        // The same click still reaches sidebar buttons, tabs, or the page.
        super.sendEvent(event)
    }

    override func close() { closing = true; super.close() }

    /// Browser commands can deliberately end the old address edit before preparing a new one.
    func clearAddressFocus() { _ = super.makeFirstResponder(nil) }

    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        if !closing && protectsAddressFocus() {
            var view = responder as? NSView
            while let candidate = view {
                if candidate is WKWebView || candidate is IKCEFPage { return false }
                view = candidate.superview
            }
            // WebKit may clear focus before asking to focus its page. Preserve an address
            // editor through that request; explicit dismissal turns protection off first.
            if responder == nil || responder === self, let root = contentView, addressOwnsResponder(in: root) { return false }
        }
        return super.makeFirstResponder(responder)
    }

    private func addressOwnsResponder(in view: NSView) -> Bool {
        if let field = view as? FocusingTextField, let editor = field.currentEditor(), firstResponder === editor { return true }
        return view.subviews.contains(where: addressOwnsResponder)
    }
}

extension NSWindow {
    /// Full screen of either kind: macOS's or Ikago's own.
    var isInFullScreen: Bool { (self as? BrowserWindow)?.isIkagoFullScreen ?? styleMask.contains(.fullScreen) }
}
