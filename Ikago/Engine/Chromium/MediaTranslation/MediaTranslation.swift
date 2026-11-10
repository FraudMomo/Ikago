import Foundation
import IKCEFBridge
import os

/// Switches the media translation layer on or off for Chromium (Settings ▸ Engine; on unless turned off). On: new X
/// pages get `MediaTranslationShim`, and `IKCEFMediaBridge` answers their translation requests with
/// `MediaTranslator`. Off: the endpoint doesn't exist, and X videos use the native overlay instead.
@MainActor
enum MediaTranslation {
    private(set) static var isEnabled = false

    /// Sizes and outcomes only: never addresses or media.
    nonisolated static let log = Logger(subsystem: "app.ikago.browser", category: "media-translation")

    static func apply(_ enabled: Bool) {
        isEnabled = enabled && BrowserRuntime.runs(.chromium)
        log.info("translation \(isEnabled ? "on" : "off", privacy: .public)")
        IKCEFMediaBridge.setHosts(MediaTranslationShim.hosts, translator: isEnabled ? { stream, body, urgent, fit, done in
            done(MediaTranslator.shared.translate(stream: stream, body, urgent: urgent, fit: Int(fit)))
        } : nil)
    }

    /// The script a new Chromium page should run before its own, if any.
    static var documentStartScript: String? { isEnabled ? MediaTranslationShim.source : nil }
}
