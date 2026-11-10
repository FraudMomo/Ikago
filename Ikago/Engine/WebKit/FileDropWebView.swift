import AppKit
import WebKit

/// WebKit owns drag hit testing inside its page; handle browser file navigation there
/// as well as on the native destination used by internal and empty pages.
final class FileDropWebView: WKWebView {
    var onFiles: ([URL]) -> Void = { _ in }

    private func files(_ sender: any NSDraggingInfo) -> [URL] {
        guard sender.draggingSourceOperationMask.contains(.copy) else { return [] }
        return LocalFileDrop.files(in: sender.draggingPasteboard)
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        files(sender).isEmpty ? super.draggingEntered(sender) : .copy
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        files(sender).isEmpty ? super.draggingUpdated(sender) : .copy
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        !files(sender).isEmpty || super.prepareForDragOperation(sender)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let urls = files(sender)
        guard !urls.isEmpty else { return super.performDragOperation(sender) }
        DispatchQueue.main.async { [onFiles] in onFiles(urls) }
        return true
    }
}
