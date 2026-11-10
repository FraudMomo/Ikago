import AppKit
import SwiftUI

extension View {
    /// Middle-click (the wheel button) runs `action`. SwiftUI has no gesture for it.
    func onMiddleClick(_ action: @escaping () -> Void) -> some View {
        overlay(MiddleClickCatcher(action: action))
    }
}

/// Transparent overlay that only takes part in hit-testing for the extra mouse buttons, so
/// clicks, hovers and drags still reach the view underneath.
private struct MiddleClickCatcher: FillingViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> CatcherView { CatcherView() }
    func updateNSView(_ view: CatcherView, context: Context) { view.action = action }

    final class CatcherView: NSView {
        var action: () -> Void = {}

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let type = NSApp.currentEvent?.type, type == .otherMouseDown || type == .otherMouseUp else { return nil }
            return super.hitTest(point)
        }

        override func otherMouseDown(with event: NSEvent) {
            if event.buttonNumber != 2 { super.otherMouseDown(with: event) }
        }

        override func otherMouseUp(with event: NSEvent) {
            if event.buttonNumber == 2 { action() } else { super.otherMouseUp(with: event) }
        }
    }
}
