import AppKit
import SwiftUI

extension BrowserWindowController {
    func openInPrivateWindow(_ url: String) {
        guard let address = URL(string: url), ["http", "https"].contains(address.scheme?.lowercased() ?? ""),
              address.user == nil, address.password == nil else { return }
        (NSApp.delegate as? AppDelegate)?.openPrivateWindow(url: address.absoluteString)
    }

    func showTabHover(_ id: String, anchor: CGRect) {
        guard state.browserPreferences.tabHoverPreviews != false,
              !chrome.inlineAddress, !chrome.showPalette, chrome.previewTabID == nil, state.tab(id) != nil,
              NSEvent.pressedMouseButtons == 0, !chrome.showDownloads else { return }
        let thumbnail = state.browserPreferences.tabPreviewThumbnails != false
        chrome.hoverCandidateID = id
        Task { @MainActor [weak self] in
            guard let self else { return }
            let image = id == self.state.activeTabID || !thumbnail ? nil : await self.previewImage(id)
            guard self.chrome.hoverCandidateID == id, !self.chrome.inlineAddress else { return }
            // The snapshot took a moment: the pointer may have left without an exit event reaching the row.
            guard self.pointerIsOver(anchor) else { return self.hideTabHover(id) }
            self.chrome.hoverTabAnchor = anchor
            self.chrome.hoverImage = image
            withAnimation(.easeOut(duration: 0.16)) { self.chrome.hoverTabID = id }
            self.watchHover(id, anchor: anchor)
        }
    }
    func hideTabHover(_ id: String) {
        if chrome.hoverCandidateID == id { chrome.hoverCandidateID = nil }
        if chrome.hoverTabID == id {
            chrome.hoverWatch?.cancel(); chrome.hoverWatch = nil
            withAnimation(.easeOut(duration: 0.12)) { chrome.hoverTabID = nil }
        }
    }

    /// Exit events alone left the card up: a row that scrolls, re-renders for another tab or leaves the window while
    /// hovered never gets one, and none arrive once the window isn't key. While the card is up, check the pointer
    /// itself a few times a second and take the card down once it is off the tab.
    private func watchHover(_ id: String, anchor: CGRect) {
        chrome.hoverWatch?.cancel()
        chrome.hoverWatch = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(150))
                guard let self, !Task.isCancelled, self.chrome.hoverTabID == id else { return }
                let active = NSApp.isActive && self.window?.isKeyWindow == true
                if !active || !self.pointerIsOver(anchor) || self.state.tab(id) == nil || NSEvent.pressedMouseButtons != 0 {
                    self.hideTabHover(id)
                    return
                }
            }
        }
    }

    /// Whether the pointer is inside `anchor` (content-view coordinates, as the rows report it).
    func pointerIsOver(_ anchor: CGRect) -> Bool {
        guard let window, let content = window.contentView else { return false }
        let point = content.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        return anchor.insetBy(dx: -2, dy: -2).contains(point)
    }
    var peekContent: NSView? { peekController?.hostView }
    var peekTab: TabItem? { peekController?.tab }
    func focusPeek() { peekController?.page?.visibilityChanged(); peekController?.focus() }
    func closePeek() {
        peekController?.hostView.removeFromSuperview()
        peekController?.page?.visibilityChanged()
        if peekIsTemporary { peekController?.close() }
        peekController = nil; peekIsTemporary = false
        withAnimation(.ikago) { chrome.previewTabID = nil }
    }
    /// Open as Tab: the card grows to exactly where the page sits, then that same live page becomes the tab, with no
    /// reload, fade or switch to see.
    func openPeek() {
        guard peekController != nil, !chrome.peekExpanding else { return }
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let target = peekTargetFrame() else { return finishOpeningPeek() }
        chrome.peekTarget = target
        withAnimation(.spring(duration: 0.36, bounce: 0)) { chrome.peekExpanding = true } completion: { [weak self] in
            self?.finishOpeningPeek()
        }
    }

    private func finishOpeningPeek() {
        guard let controller = peekController else { chrome.peekExpanding = false; return }
        var instant = Transaction(); instant.disablesAnimations = true
        withTransaction(instant) {
            content.switchesInstantly = true
            if peekIsTemporary {
                // The previewed page itself moves into the tab list (as a tab moving between windows does), placed
                // where a link opened from the current tab would go.
                peekController = nil; peekIsTemporary = false
                let peeked = controller.tab
                if let opener = state.activeTab, let tab = state.newTabFromLink(url: peeked.url, opener: opener, select: false) {
                    tab.title = peeked.title
                    tab.faviconURL = peeked.faviconURL
                    content.adopt(tab, fromPeek: controller)
                    state.select(tab.id)
                } else {
                    content.adopt(peeked, fromPeek: controller)
                    state.adoptTab(peeked)
                }
            } else {
                controller.hostView.removeFromSuperview()
                peekController = nil
                state.select(controller.tab.id)
            }
            chrome.previewTabID = nil
            chrome.peekExpanding = false
        }
    }

    /// The page area in the shell's coordinates (top-left origin), where the grown card lands.
    private func peekTargetFrame() -> CGRect? {
        guard let shell = background.shell, content.pageArea.window != nil else { return nil }
        let rect = shell.convert(content.pageArea.bounds, from: content.pageArea)
        let top = shell.isFlipped ? rect.minY : shell.bounds.height - rect.maxY
        let frame = CGRect(x: rect.minX, y: top, width: rect.width, height: rect.height)
        return frame.width > 0 && frame.height > 0 ? frame : nil
    }
    func peekLink(_ url: String) {
        guard AddressResolver.isWebURL(url) else { return }
        closePeek()
        let tab = TabItem(url: url, spaceID: state.activeSpaceID)
        let controller = TabController(tab: tab, state: state, host: self)
        peekController = controller; peekIsTemporary = true
        controller.startIfNeeded()
        withAnimation(.spring(duration: 0.34, bounce: 0.12)) { chrome.previewTabID = tab.id }
    }
    func peekTab(_ id: String) {
        chrome.hoverTabID = nil
        guard id != state.activeTabID, let controller = content.controller(for: id) else { return }
        closePeek(); peekController = controller
        controller.startIfNeeded()
        withAnimation(.ikago) { chrome.previewTabID = id }
    }
    func previewImage(_ id: String) async -> NSImage? {
        guard let controller = content.controller(for: id), let page = controller.page,
              !controller.tab.isHibernating, let snapshot = try? await page.snapshot(),
              !Task.isCancelled, content.controller(for: id)?.page === page else { return nil }
        let size = snapshot.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(1, 640 / max(size.width, size.height))
        let target = NSSize(width: size.width * scale, height: size.height * scale)
        let thumbnail = NSImage(size: target)
        thumbnail.lockFocus()
        snapshot.draw(in: NSRect(origin: .zero, size: target))
        thumbnail.unlockFocus()
        return thumbnail
    }
}
