import AppKit

extension CEFWebTab {
    var performanceProcessID: Int32? { page.rendererProcessID > 0 ? Int32(page.rendererProcessID) : nil }
}

extension WebKitTab {
    var performanceProcessID: Int32? {
        // SPI: WebKit has no public tab-to-renderer mapping. Used only by visible diagnostics and demand-driven tab previews.
        let selector = NSSelectorFromString("_webProcessIdentifier")
        guard webView.responds(to: selector), let implementation = webView.method(for: selector) else { return nil }
        typealias Getter = @convention(c) (AnyObject, Selector) -> Int32
        let pid = unsafeBitCast(implementation, to: Getter.self)(webView, selector)
        return pid > 0 ? pid : nil
    }
}
