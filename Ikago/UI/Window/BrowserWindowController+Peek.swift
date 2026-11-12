import AppKit

extension BrowserWindowController {
    func peekTab(_ id: String) {
        guard state.tab(id) != nil else { return }
        chrome.previewTabID = id
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
