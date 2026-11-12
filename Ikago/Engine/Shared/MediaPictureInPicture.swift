import AppKit
import WebKit

/// Invoked only by the browser's PiP button; never depends on a site's context menu.
@MainActor
enum MediaPictureInPicture {
    static let source = """
    const videos = [...document.querySelectorAll('video')].filter(v => v.readyState > 0);
    const video = videos.find(v => !v.paused && !v.ended) || videos[0];
    if (!video) return {video:false};
    if (video.webkitSupportsPresentationMode?.('picture-in-picture') && video.webkitSetPresentationMode) {
      video.webkitSetPresentationMode(video.webkitPresentationMode === 'picture-in-picture' ? 'inline' : 'picture-in-picture');
      return {video:true, native:true};
    }
    return {video:true, source:video.currentSrc || video.src || ''};
    """
    static func finish(_ result: Any?, page: WebTab) throws {
        guard let report = result as? [String: Any], report["video"] as? Bool == true else { throw Issue.noVideo }
        if report["native"] as? Bool == true { return }
        guard let address = report["source"] as? String, let url = URL(string: address),
              ["https", "http"].contains(url.scheme ?? "") else { throw Issue.managedStream }
        NativePictureInPicture.shared.open(address, owner: page, window: page.contentView.window)
    }
    enum Issue: LocalizedError {
        case noVideo, managedStream
        var errorDescription: String? {
            switch self {
            case .noVideo: "No ready video was found in this player."
            case .managedStream: "This page-managed stream can’t be opened by the native player on this engine."
            }
        }
    }
}

extension WebTab {
    func pictureInPicture() async throws {
        try MediaPictureInPicture.finish(try await callAsync(MediaPictureInPicture.source), page: self)
    }
}

extension WebKitTab {
    func pictureInPicture() async throws {
        // SPI: macOS has no public native PiP toggle for MSE streams. Guard every selector.
        let update = NSSelectorFromString("_updateMediaPlaybackControlsManager")
        let can = NSSelectorFromString("_canTogglePictureInPicture")
        let toggle = NSSelectorFromString("_togglePictureInPicture")
        if webView.responds(to: update) { webView.perform(update); try? await Task.sleep(for: .milliseconds(80)) }
        if webView.responds(to: can), webView.responds(to: toggle), let implementation = webView.method(for: can) {
            typealias Getter = @convention(c) (AnyObject, Selector) -> Bool
            if unsafeBitCast(implementation, to: Getter.self)(webView, can) { webView.perform(toggle); return }
        }
        let frames = audibleFrames.values.filter { $0.playback.hasVideo }
        if let frame = frames.first(where: { $0.playback.playing }) ?? frames.first {
            let result = try await webView.callAsyncJavaScript(MediaPictureInPicture.source, arguments: [:],
                in: frame.frame.isMainFrame ? nil : frame.frame, contentWorld: .defaultClient)
            try MediaPictureInPicture.finish(result, page: self)
        } else {
            try MediaPictureInPicture.finish(try await callAsync(MediaPictureInPicture.source), page: self)
        }
    }
}
