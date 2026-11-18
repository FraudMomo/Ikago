import AppKit
import SwiftUI

/// Switching between Sidebar and Top Tabs. The new layout is built in one frame without animating any geometry,
/// and the window cross-fades from the old picture to the new one (a Core Animation transition on the window's layer,
/// done by the GPU). Animating it instead resized every page and rebuilt the sidebar's list on each frame: measured
/// 5–9 missed frames per switch (`layoutprobe`).
@MainActor
enum LayoutSwitch {
    static let duration: CFTimeInterval = 0.24

    static func set(tabs: Bool, state: BrowserState) {
        guard (state.browserPreferences.sidebarTopTabs == true) != tabs else { return }
        let window = NSApp.windows.first { ($0.windowController as? BrowserWindowController)?.state === state }
        let content = window?.contentView
        CATransaction.begin()
        if let layer = content?.layer, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let fade = CATransition()
            fade.type = .fade
            fade.duration = duration
            fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(fade, forKey: "ikago-layout-switch")
        }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { state.browserPreferences.sidebarTopTabs = tabs ? true : nil }
        // Build the new layout now, inside this transaction, so the fade has both pictures.
        content?.layoutSubtreeIfNeeded()
        CATransaction.commit()
    }
}
