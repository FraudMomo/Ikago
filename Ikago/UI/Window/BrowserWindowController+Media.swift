import Foundation

extension BrowserWindowController {
    @objc func askThisPage(_ sender: Any?) { chrome.showPageAssistant.toggle() }

    func controlMedia(_ id: String, action: MediaPlaybackAction) {
        guard let page = content.controller(for: id)?.page else { return }
        Task { @MainActor in await page.controlMedia(action) }
    }
}
