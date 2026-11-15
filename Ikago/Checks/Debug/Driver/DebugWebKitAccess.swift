#if DEBUG
import WebKit

/// The Debug test driver exercises the WebKit engine directly, so its checks reach through the
/// engine-neutral page interface here. Running them on the Chromium engine is a programming error.
extension WebTab {
    var webView: WKWebView { (self as! WebKitTab).webView }
    var externalLinks: ExternalLinkOpener {
        get { (self as! WebKitTab).externalLinks }
        set { (self as! WebKitTab).externalLinks = newValue }
    }
}
#endif
