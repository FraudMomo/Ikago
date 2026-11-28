import AppKit
import WebKit
import IKCEFBridge

/// Reject page focus before NSWindow resigns the address editor. A WKWebView responder
/// override alone runs too late: refusing there can already leave the window without an editor.
@MainActor
final class BrowserWindow: NSWindow {
    var protectsAddressFocus: @MainActor () -> Bool = { false }
    var dismissAddress: @MainActor () -> Void = {}
    /// Letters typed after ⌘L or ⌘T before the address field has the keyboard: they go to the field's text instead
    /// of nowhere. True when taken.
    var typeAhead: @MainActor (String) -> Bool = { _ in false }
    private var closing = false
    /// Ikago's own full screen (`IkagoFullScreen`) instead of macOS's, which slides its titlebar over the bars.
    var fullScreenHandler: (@MainActor () -> Void)?
    /// In Ikago's full screen: the window covers the display and the frame isn't kept below the menu bar.
    var isIkagoFullScreen = false
    /// Height of the band the bars leave above them in Ikago's full screen (the camera housing).
    var fullScreenTopBand: CGFloat = 0
    static let willExitIkagoFullScreen = Notification.Name("app.ikago.willExitFullScreen")

    /// Movable for macOS's window management (Window ▸ Fill, Center, Move & Resize, another display, tiling, which it
    /// offers only for a movable window), but not while a press is handled: then only the empty chrome moves it
    /// (`WindowDragArea` and `PageWindowGrab` allow it for their own drag), so tabs and buttons never drag the window.
    override var isMovable: Bool {
        get { allowsDragFromPress || !handlingPress }
        set { allowsDragFromPress = newValue }
    }
    private var allowsDragFromPress = false
    private var handlingPress = false

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
        if event.type == .keyDown, protectsAddressFocus(), !(firstResponder is NSTextView),
           event.modifierFlags.isDisjoint(with: [.command, .control, .option, .function]),
           let characters = event.characters, !characters.isEmpty,
           characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) && $0.value < 0xF700 }),
           typeAhead(characters) {
            return
        }
        if [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type),
           protectsAddressFocus(), let root = contentView,
           !AddressRegionView.contains(event.locationInWindow, in: root) {
            dismissAddress()
        }
        // The same click still reaches sidebar buttons, tabs, or the page.
        let press = event.type == .leftMouseDown
        if press { handlingPress = true }
        defer { if press { handlingPress = false } }
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
