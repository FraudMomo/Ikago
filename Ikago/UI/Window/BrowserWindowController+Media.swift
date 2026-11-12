import Foundation

extension BrowserWindowController {
    func controlMedia(_ id: String, action: MediaPlaybackAction) {
        guard let page = content.controller(for: id)?.page else { return }
        Task { @MainActor in await page.controlMedia(action) }
    }
}
