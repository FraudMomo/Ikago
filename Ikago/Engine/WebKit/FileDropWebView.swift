import AppKit
import WebKit

/// WebKit owns drag hit testing inside its page, so file drops go to the page first; a file the page doesn't take opens
/// as a tab (internal and empty pages use `FileDropHostingView`).
final class FileDropWebView: WKWebView {
    var pageAction: (PageContextAction) -> Void = { _ in }
    var menuActions: [PageMenuAction] = []
    var onFiles: ([URL]) -> Void = { _ in }
    var onNotification: (String) -> Void = { _ in }

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        configurePageMenu(menu, event: event)
    }

    /// Files from the drop in progress. The page gets the drop first (an upload area takes it); only when WebKit
    /// would load a dropped file in place does the tab open the files instead (`consumeDroppedFileNavigation`).
    private var droppedFiles: [URL] = []
    private var droppedAt = Date.distantPast

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        if sender.draggingSourceOperationMask.contains(.copy) {
            droppedFiles = LocalFileDrop.files(in: sender.draggingPasteboard)
            droppedAt = Date()
        }
        return super.performDragOperation(sender)
    }

    /// True when a main-frame navigation to `url` is WebKit loading a file the page didn't take; the files then open
    /// the browser's way (new tabs) and the navigation is cancelled.
    func consumeDroppedFileNavigation(to url: URL) -> Bool {
        guard url.isFileURL, !droppedFiles.isEmpty, Date().timeIntervalSince(droppedAt) < 2,
              droppedFiles.contains(where: { $0.standardizedFileURL == url.standardizedFileURL }) else { return false }
        let urls = droppedFiles
        droppedFiles = []
        DispatchQueue.main.async { [onFiles] in onFiles(urls) }
        return true
    }
}
