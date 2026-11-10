import AppKit
import UniformTypeIdentifiers
import SwiftUI

/// Native file URLs only: tab drags, text and promised files keep their existing destinations.
enum LocalFileDrop {
    static func files(in pasteboard: NSPasteboard) -> [URL] {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.filter { url in
            guard AddressResolver.isLocalFileURL(url.absoluteString),
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentTypeKey]),
                  values.isRegularFile == true else { return false }
            if ["html", "htm", "shtml", "xhtml", "xht", "xhtm"].contains(url.pathExtension.lowercased()) { return true }
            guard let type = values.contentType else { return false }
            return type.conforms(to: .text) || type.conforms(to: .image) || type.conforms(to: .pdf)
                || type.conforms(to: .audiovisualContent) || type.identifier == "com.apple.webarchive"
        }
    }
}

/// Internal/empty/error pages also participate without an overlay intercepting their controls.
final class FileDropHostingView<Content: View>: NSHostingView<Content> {
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
