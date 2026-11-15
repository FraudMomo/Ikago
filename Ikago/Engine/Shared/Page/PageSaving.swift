import AppKit
import UniformTypeIdentifiers

/// What File ▸ Save Page As… can write: the page with its resources in one file, or the page as a paginated PDF.
enum PageSaveFormat: Int, CaseIterable {
    case archive, pdf

    func title(for engine: BrowserEngine) -> String {
        switch self {
        case .archive: engine == .chromium ? "Web Archive (MHTML)" : "Web Archive"
        case .pdf: "PDF Document"
        }
    }

    func fileExtension(for engine: BrowserEngine) -> String {
        switch self {
        case .archive: engine == .chromium ? "mhtml" : "webarchive"
        case .pdf: "pdf"
        }
    }

    func contentType(for engine: BrowserEngine) -> UTType {
        UTType(filenameExtension: fileExtension(for: engine)) ?? (self == .pdf ? .pdf : .data)
    }
}

/// Save Page As…: asks where, then has the page write itself, on either engine.
@MainActor
enum PageSaver {
    static func save(_ page: WebTab, title: String, in window: NSWindow?) {
        guard let window else { return }
        let panel = NSSavePanel()
        panel.title = "Save Page As"
        panel.canCreateDirectories = true
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        let engine = page.engine
        let format = FormatChoice(engine: engine) { [weak panel] format in
            guard let panel else { return }
            panel.allowedContentTypes = [format.contentType(for: engine)]
            let name = (panel.nameFieldStringValue as NSString).deletingPathExtension
            panel.nameFieldStringValue = name + "." + format.fileExtension(for: engine)
        }
        panel.accessoryView = format.view
        panel.nameFieldStringValue = fileName(title, page.currentURL) + "." + PageSaveFormat.archive.fileExtension(for: engine)
        panel.allowedContentTypes = [PageSaveFormat.archive.contentType(for: engine)]
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            let chosen = format.selected
            Task { @MainActor in
                do { try await page.savePage(as: chosen, to: url) }
                catch {
                    let alert = NSAlert()
                    alert.messageText = "The page couldn’t be saved"
                    alert.informativeText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    alert.beginSheetModal(for: window, completionHandler: nil)
                }
            }
        }
    }

    /// A safe file name from the page title, or its host.
    static func fileName(_ title: String, _ address: String) -> String {
        let source = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (URL(string: address)?.host() ?? "Page") : title
        let cleaned = source.components(separatedBy: CharacterSet(charactersIn: "/:\\\n\r\t")).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: ".")))
        return String((cleaned.isEmpty ? "Page" : cleaned).prefix(120))
    }
}

/// The save panel's format menu.
@MainActor
private final class FormatChoice: NSObject {
    let view: NSView
    private let popup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let changed: (PageSaveFormat) -> Void

    init(engine: BrowserEngine, changed: @escaping (PageSaveFormat) -> Void) {
        self.changed = changed
        let label = NSTextField(labelWithString: "Format:")
        popup.addItems(withTitles: PageSaveFormat.allCases.map { $0.title(for: engine) })
        let stack = NSStackView(views: [label, popup])
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        view = stack
        super.init()
        popup.target = self
        popup.action = #selector(choose(_:))
    }

    var selected: PageSaveFormat { PageSaveFormat(rawValue: popup.indexOfSelectedItem) ?? .archive }
    @objc private func choose(_ sender: Any?) { changed(selected) }
}

enum PageSaveError: LocalizedError {
    case failed
    var errorDescription: String? { "The page didn’t finish loading or the file couldn’t be written." }
}
