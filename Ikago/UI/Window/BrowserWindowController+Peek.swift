import AppKit
import SwiftUI

extension BrowserWindowController {
    func openInPrivateWindow(_ url: String) {
        guard let address = URL(string: url), ["http", "https"].contains(address.scheme?.lowercased() ?? ""),
              address.user == nil, address.password == nil else { return }
        (NSApp.delegate as? AppDelegate)?.openPrivateWindow(url: address.absoluteString)
    }

    func showTabHover(_ id: String, anchor: CGRect) {
        guard !chrome.inlineAddress, !chrome.showPalette, chrome.previewTabID == nil, state.tab(id) != nil,
              NSEvent.pressedMouseButtons == 0, !chrome.showDownloads else { return }
        chrome.hoverCandidateID = id
        Task { @MainActor [weak self] in
            guard let self else { return }
            let image = id == self.state.activeTabID ? nil : await self.previewImage(id)
            guard self.chrome.hoverCandidateID == id, !self.chrome.inlineAddress else { return }
            self.chrome.hoverTabAnchor = anchor
            self.chrome.hoverImage = image
            withAnimation(.easeOut(duration: 0.16)) { self.chrome.hoverTabID = id }
        }
    }
    func hideTabHover(_ id: String) {
        if chrome.hoverCandidateID == id { chrome.hoverCandidateID = nil }
        if chrome.hoverTabID == id { withAnimation(.easeOut(duration: 0.12)) { chrome.hoverTabID = nil } }
    }
    var peekContent: NSView? { peekController?.hostView }
    func focusPeek() { peekController?.page?.visibilityChanged(); peekController?.focus() }
    func closePeek() {
        peekController?.hostView.removeFromSuperview()
        peekController?.page?.visibilityChanged()
        if peekIsTemporary { peekController?.close() }
        peekController = nil; peekIsTemporary = false
        withAnimation(.ikago) { chrome.previewTabID = nil }
    }
    func openPeek() {
        guard let controller = peekController else { return }
        let id = controller.tab.id, url = controller.tab.url, temporary = peekIsTemporary
        closePeek()
        if temporary { state.newTab(url: url) } else { state.select(id) }
    }
    func peekLink(_ url: String) {
        guard AddressResolver.isWebURL(url) else { return }
        closePeek()
        let tab = TabItem(url: url, spaceID: state.activeSpaceID)
        let controller = TabController(tab: tab, state: state, host: self)
        peekController = controller; peekIsTemporary = true
        controller.startIfNeeded()
        withAnimation(.ikago) { chrome.previewTabID = tab.id }
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
