import AppKit
import PDFKit
import UniformTypeIdentifiers

/// What Save Page can make of a page (`SavePageSheet`): the page itself (a web archive with every resource, its HTML, or
/// its text), a PDF (printable pages, or one long page), or an image (the whole page, or what is on screen).
enum PageSaveFormat: String, CaseIterable, Identifiable {
    case archive, html, text, pdf, longPDF, fullPNG, fullJPEG, visiblePNG, visibleJPEG
    var id: String { rawValue }

    var isImage: Bool { [.fullPNG, .fullJPEG, .visiblePNG, .visibleJPEG].contains(self) }
    var isJPEG: Bool { self == .fullJPEG || self == .visibleJPEG }

    func title(for engine: BrowserEngine) -> String {
        switch self {
        case .archive: engine == .chromium ? "Web Archive (MHTML)" : "Web Archive"
        case .html: "HTML"
        case .text: "Text"
        case .pdf: "PDF"
        case .longPDF: "Long PDF"
        case .fullPNG, .fullJPEG: "Full Page"
        case .visiblePNG, .visibleJPEG: "Visible Area"
        }
    }

    func fileExtension(for engine: BrowserEngine) -> String {
        switch self {
        case .archive: engine == .chromium ? "mhtml" : "webarchive"
        case .html: "html"
        case .text: "txt"
        case .pdf, .longPDF: "pdf"
        case .fullPNG, .visiblePNG: "png"
        case .fullJPEG, .visibleJPEG: "jpg"
        }
    }

    func contentType(for engine: BrowserEngine) -> UTType {
        UTType(filenameExtension: fileExtension(for: engine)) ?? .data
    }

    /// The same image of the page in the other file type.
    func withJPEG(_ jpeg: Bool) -> PageSaveFormat {
        switch self {
        case .fullPNG, .fullJPEG: jpeg ? .fullJPEG : .fullPNG
        case .visiblePNG, .visibleJPEG: jpeg ? .visibleJPEG : .visiblePNG
        default: self
        }
    }
}

extension WebTab {
    /// Writes the page to `url` in `format`.
    func savePage(as format: PageSaveFormat, to url: URL) async throws {
        try await exportPage(format).write(to: url, options: .atomic)
    }
}

/// Scripts and image steps both engines share for saving.
@MainActor
enum PageExport {
    /// The document as HTML: its doctype, then its markup as it is now.
    static let htmlScript = """
    (document.doctype ? new XMLSerializer().serializeToString(document.doctype) + '\\n' : '') + document.documentElement.outerHTML
    """
    /// The page's readable text, as the person sees it.
    static let textScript = "document.body ? document.body.innerText : document.documentElement.innerText"
    /// The whole document's size in CSS pixels.
    static let sizeScript = "[Math.max(document.documentElement.scrollWidth, document.body ? document.body.scrollWidth : 0), "
        + "Math.max(document.documentElement.scrollHeight, document.body ? document.body.scrollHeight : 0)]"
    /// Images are kept under this many pixels tall; past it, the page is drawn at a smaller scale (very long pages).
    static let longestImage: CGFloat = 16_384

    static func string(_ value: Any?) throws -> Data {
        guard let text = value as? String, let data = text.data(using: .utf8) else { throw PageSaveError.failed }
        return data
    }

    /// An image as PNG, or JPEG at high quality.
    static func encode(_ image: CGImage, jpeg: Bool) throws -> Data {
        let representation = NSBitmapImageRep(cgImage: image)
        guard let data = representation.representation(using: jpeg ? .jpeg : .png, properties: jpeg ? [.compressionFactor: 0.9] : [:])
        else { throw PageSaveError.failed }
        return data
    }

    static func encode(_ image: NSImage, jpeg: Bool) throws -> Data {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw PageSaveError.failed }
        return try encode(cgImage, jpeg: jpeg)
    }

    /// A one-page PDF drawn as an image: at twice its size (Retina), smaller when that would be too tall, on white.
    static func rasterize(pdf data: Data) throws -> CGImage {
        // The document stays alive while its page draws (a page can't draw without it).
        guard let document = PDFDocument(data: data), let page = document.page(at: 0) else { throw PageSaveError.failed }
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { throw PageSaveError.failed }
        let scale = min(2, longestImage / bounds.height)
        let width = Int(bounds.width * scale), height = Int(bounds.height * scale)
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { throw PageSaveError.failed }
        context.setFillColor(.white)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -bounds.minX, y: -bounds.minY)
        page.draw(with: .mediaBox, to: context)
        withExtendedLifetime(document) {}
        guard let image = context.makeImage() else { throw PageSaveError.failed }
        return image
    }
}

/// Saving and copying from Save Page: where to (the save panel, its name filled in from the page), then the page writes
/// itself, on either engine.
@MainActor
enum PageSaver {
    static func save(_ page: WebTab, format: PageSaveFormat, title: String, in window: NSWindow?) async throws -> Bool {
        let engine = page.engine
        let panel = NSSavePanel()
        panel.title = "Save Page"
        panel.canCreateDirectories = true
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        panel.nameFieldStringValue = fileName(title, page.currentURL) + "." + format.fileExtension(for: engine)
        panel.allowedContentTypes = [format.contentType(for: engine)]
        let response: NSApplication.ModalResponse
        if let window { response = await panel.beginSheetModal(for: window) } else { response = panel.runModal() }
        guard response == .OK, let url = panel.url else { return false }
        try await page.savePage(as: format, to: url)
        return true
    }

    /// Puts the page on the clipboard: an image as an image, text and HTML as text.
    static func copy(_ page: WebTab, format: PageSaveFormat) async throws {
        let data = try await page.exportPage(format)
        let board = NSPasteboard.general
        board.clearContents()
        if format.isImage {
            guard let image = NSImage(data: data) else { throw PageSaveError.failed }
            board.writeObjects([image])
        } else {
            board.setString(String(decoding: data, as: UTF8.self), forType: .string)
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

enum PageSaveError: LocalizedError {
    case failed
    var errorDescription: String? { "The page didn’t finish loading or the file couldn’t be written." }
}
