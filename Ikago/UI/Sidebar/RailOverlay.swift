import AppKit
import SwiftUI

/// The window the icon sidebar's Expand is drawn in (`RailHover`): borderless, transparent, a child of the browser
/// window and exactly its size, so both share coordinates. The window server gives it the pointer only where it draws,
/// so the page under the wider rail gets no moves and stops hovering, and everywhere else the browser window gets the
/// pointer as if it weren't there. It is put in place, invisible, as the pointer arrives on the rail and shown only
/// while the effects show (`RailHoverModel.shown`).
@MainActor
final class RailOverlay {
    private let panel: RailOverlayPanel
    private weak var parent: NSWindow?
    private var observers: [NSObjectProtocol] = []

    init<Content: View>(parent: NSWindow, content: Content) {
        self.parent = parent
        panel = RailOverlayPanel(contentRect: parent.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isExcludedFromWindowsMenu = true
        panel.animationBehavior = .none
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]
        let host = RailOverlayHost(rootView: content)
        host.sizingOptions = []
        panel.contentView = host
        let center = NotificationCenter.default
        for name in [NSWindow.didResizeNotification, NSWindow.didEndLiveResizeNotification, NSWindow.didEnterFullScreenNotification,
                     NSWindow.didExitFullScreenNotification, NSWindow.didChangeScreenNotification] {
            observers.append(center.addObserver(forName: name, object: parent, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.fit() }
            })
        }
    }

    /// Puts the window in place over the browser window, invisible and letting the pointer through, so it has drawn
    /// before it shows. It stays there once it has been needed: showing is then only its alpha.
    func prepare() {
        guard let parent, panel.parent == nil, parent.isVisible else { return }
        fit()
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true
        panel.appearance = parent.effectiveAppearance
        parent.addChildWindow(panel, ordered: .above)
        panel.orderFront(nil)
    }

    /// Shows the effects' window, or hides it (invisible, the pointer going through).
    func show(_ shown: Bool) {
        if shown {
            prepare()
            fit()
            panel.alphaValue = 1
        } else {
            panel.alphaValue = 0
            panel.ignoresMouseEvents = true
        }
    }

    /// Lets the pointer through to the browser window everywhere, or (false) takes it where the effects draw.
    func passThrough(_ through: Bool) {
        if panel.ignoresMouseEvents != through { panel.ignoresMouseEvents = through }
    }

    var isShown: Bool { panel.parent != nil && panel.isVisible && panel.alphaValue > 0 }

    private func fit() {
        guard let parent, panel.frame != parent.frame else { return }
        panel.setFrame(parent.frame, display: false)
    }
}

/// Takes the first click: the overlay is never the key window, and a click on it is always meant for what it shows.
private final class RailOverlayHost<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Never key or main: the browser window keeps the focus while the effects are used.
private final class RailOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
