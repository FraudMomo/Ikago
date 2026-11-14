import AppKit

/// More than one regular window (`BrowserWindows`): New Window, Move Tab to New Window, and the window events that keep
/// the session's record of each window current.
extension BrowserWindowController {
    @objc func newWindow(_ sender: Any?) {
        guard let window = BrowserWindows.open() else { return }
        window.newTab()
    }

    @objc func moveTabToNewWindow(_ sender: Any?) {
        if let id = state.activeTabID { moveToNewWindow(id) }
    }

    func moveToNewWindow(_ id: String) { BrowserWindows.moveToNewWindow(id, from: self) }

    /// A tab dragged from this window and dropped outside every Ikago window.
    func tabDraggedOut(_ id: String, at point: NSPoint) {
        // A drop inside a window reads the selection later (its payload arrives after this check, measured): leave it.
        guard BrowserWindows.window(at: point) == nil else { return }
        let companions = TabDrag.companions
        TabDrag.companions = []
        chrome.selectedTabIDs = []
        BrowserWindows.tearOff(id, from: self, at: point, with: companions)
    }

    // MARK: NSWindowDelegate

    func windowDidBecomeKey(_ notification: Notification) {
        applyFullScreenPresentation()
        positionTrafficLights()
        // Extensions open their tabs in the regular window in front.
        if !state.isPrivate { ExtensionManager.shared.browser = self }
        ExtensionManager.shared.windowFocused(self)
    }

    func windowDidResignKey(_ notification: Notification) {
        applyFullScreenPresentation()
    }

    /// Closing the first window while others are open keeps the session's owner: it takes over another window instead.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        !(BrowserWindows.primary === self && BrowserWindows.handOver(closing: self))
    }

    func windowDidMove(_ notification: Notification) { recordFrame() }
    func windowDidEndLiveResize(_ notification: Notification) { recordFrame() }

    private func recordFrame() {
        guard state.primary != nil, let frame = window?.frame, browserWindow?.isIkagoFullScreen != true else { return }
        state.windowFrame = frame
        state.scheduleSave()
    }
}
