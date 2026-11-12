import AppKit
import SwiftUI

extension BrowserWindowController {
    func togglePageAssistant() {
        guard state.browserPreferences.pageIntelligence == true else { chrome.showPageAssistant = false; return }
        withAnimation(.ikago) { chrome.showPageAssistant.toggle() }
    }
    @objc func askThisPage(_ sender: Any?) { togglePageAssistant() }

    func pictureInPicture(_ id: String) {
        guard let page = content.controller(for: id)?.page else { return }
        Task { @MainActor [weak self] in
            do { try await page.pictureInPicture() }
            catch {
                guard let window = self?.window else { return }
                let alert = NSAlert(error: error)
                alert.messageText = "Picture in Picture Unavailable"
                alert.beginSheetModal(for: window) { _ in }
            }
        }
    }

    func controlMedia(_ id: String, action: MediaPlaybackAction) {
        guard let page = content.controller(for: id)?.page else { return }
        Task { @MainActor in await page.controlMedia(action) }
    }
}
