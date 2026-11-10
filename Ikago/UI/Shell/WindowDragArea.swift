import AppKit
import SwiftUI

/// Empty chrome you can grab: drag to move the window, double-click to zoom it (like a titlebar).
/// An AppKit view placed behind a bar's content, so only clicks that reach it (empty space) move the window.
struct WindowDragArea: FillingViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) {}

    final class DragView: NSView {
        override var isFlipped: Bool { true }

        // The window is not movable (see BrowserWindowController), so nothing else can start a
        // drag. Here it is movable just for the system drag: edge tiling, snapping and
        // Option-arrange all work, as in a native title bar.
        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            if event.clickCount == 2 { window.zoom(nil); return }
            window.isMovable = true
            window.performDrag(with: event)
            window.isMovable = false
        }
    }
}
