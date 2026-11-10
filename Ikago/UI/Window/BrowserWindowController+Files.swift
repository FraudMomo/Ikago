import AppKit

extension BrowserWindowController {
    func openDroppedFiles(_ urls: [URL]) {
        let files = urls.filter { AddressResolver.isLocalFileURL($0.absoluteString) }
        guard let first = files.first else { return }
        dismissCommandPalette()
        // Preserve pinned pages through the shared address-navigation guard.
        open(first.absoluteString, inNewTab: false)
        for file in files.dropFirst() { _ = state.newTab(url: file.absoluteString, select: false) }
        window?.makeKeyAndOrderFront(nil)
    }
}
