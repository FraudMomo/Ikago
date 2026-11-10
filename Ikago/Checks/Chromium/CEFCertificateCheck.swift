import AppKit
import IKCEFBridge

@MainActor
enum CEFCertificateCheck {
    static func run(profile: String) async throws {
        guard let index = CommandLine.arguments.firstIndex(of: "--cef-smoke-untrusted-url"), CommandLine.arguments.indices.contains(index + 1) else { return }
        let page = try IKCEFPage.make(profile: profile)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = page
        defer { page.close(); window.contentView = nil }
        for _ in 0..<100 { if page.ready { break }; try await Task.sleep(for: .milliseconds(50)) }
        var rejected = false
        page.eventHandler = { name, payload in
            if name == "failure", let code = payload["code"] as? Int, (-299 ... -200).contains(code) { rejected = true }
        }
        page.loadURL(CommandLine.arguments[index + 1])
        for _ in 0..<100 { if rejected { print("CEF_CERTIFICATE_REJECTION_OK"); return }; try await Task.sleep(for: .milliseconds(50)) }
        throw CEFError.script("The untrusted HTTPS certificate was not rejected.")
    }
}
