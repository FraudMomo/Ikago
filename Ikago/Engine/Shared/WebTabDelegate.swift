import AppKit
import WebKit

/// Events a page reports to its owner (TabController). All on the main actor.
@MainActor
protocol WebTabDelegate: AnyObject {
    func webTab(_ page: WebTab, didChangeTitle title: String)
    func webTab(_ page: WebTab, didChangeURL url: String)
    /// A page actually loaded in the main frame (not a provisional load or a download).
    func webTab(_ page: WebTab, didCommit url: String)
    func webTab(_ page: WebTab, didChangeProgress progress: Double)
    func webTab(_ page: WebTab, didChangeLoading isLoading: Bool, canGoBack: Bool, canGoForward: Bool)
    /// `url` is the address that failed (WebKit's `url` reverts to the previous page).
    func webTab(_ page: WebTab, didFailLoad message: String, url: String?)
    /// A main-frame navigation is about to happen. True stops it and shows a warning instead.
    func webTab(_ page: WebTab, blocksUnsafeNavigation url: URL) -> Bool
    /// A main-frame navigation to a site another engine opens (`SiteEngines`). True cancels it here: the tab
    /// reopens it in that engine.
    func webTab(_ page: WebTab, handsOff url: URL, method: String) -> Bool
    /// A link opening in a new tab leads to a site another engine opens: open it as a new tab there instead.
    func webTab(_ page: WebTab, usesOtherEngine url: URL) -> Bool
    /// HTTPS-only mode is retrying this HTTP address over HTTPS, in case that fails.
    func webTab(_ page: WebTab, willUpgradeToHTTPS url: URL)
    /// A site wants to save a file. Asks the person the first time.
    func webTab(_ page: WebTab, mayDownload url: URL?) async -> Bool
    func webTab(_ page: WebTab, didFindFavicon url: URL?)
    /// The page's theme-color metadata changed (nil when it has none).
    func webTab(_ page: WebTab, didChangeThemeColor color: NSColor?)
    /// WebKit's `hasOnlySecureContent` changed (mixed content loaded, or a new page committed).
    func webTab(_ page: WebTab, didChangeSecureContent secure: Bool)
    /// window.open / target=_blank (already user-gesture checked by WebKit). Return the
    /// adopted tab's web view, created with `configuration`, or nil to drop the popup.
    func webTab(_ page: WebTab, popupWith configuration: WKWebViewConfiguration, url: String, background: Bool) -> WKWebView?
    func webTab(_ page: WebTab, adoptCEFPopup child: CEFWebTab, url: String, background: Bool) -> Bool
    /// Cmd-click and similar: open `url` in a new tab without an opener.
    func webTab(_ page: WebTab, navigateToExtension url: String)
    func webTab(_ page: WebTab, openInNewTab url: String, background: Bool)
    func webTab(_ page: WebTab, requestsPermission request: PermissionRequest)
    func webTab(_ page: WebTab, didFind found: Bool)
    /// Audible media, camera or microphone use changed (a capture is `.active`, `.muted` or `.none`).
    func webTab(_ page: WebTab, didChangeMedia audible: Bool, camera: WKMediaCaptureState, microphone: WKMediaCaptureState)
    func webTab(_ page: WebTab, didChangePlayback playback: MediaPlaybackState)
    /// The page called window.close().
    func webTabDidClose(_ page: WebTab)
    func webTab(_ page: WebTab, didDropFiles urls: [URL])
    /// The pointer moved onto a link (its address), or off links (nil). For the status bar.
    func webTab(_ page: WebTab, didHoverLink url: String?)
}

