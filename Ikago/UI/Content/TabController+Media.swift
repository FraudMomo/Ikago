import Foundation

extension TabController {
    func webTab(_ page: WebTab, didChangePlayback playback: MediaPlaybackState) {
        guard page === self.page, tab.playback != playback else { return }
        tab.playback = playback
    }
}
