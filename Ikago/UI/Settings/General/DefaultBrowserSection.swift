import AppKit
import CoreServices
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class DefaultBrowserSetting {
    private(set) var isDefault = false
    private(set) var isRegistered = false
    private(set) var changing = false
    private(set) var message: String?
    @ObservationIgnored private let application: URL
    @ObservationIgnored private let handler: (String) -> URL?
    @ObservationIgnored private let request: (URL, String) async throws -> Void

    @ObservationIgnored private let candidates: (String) -> [URL]
    @ObservationIgnored private let register: (URL) throws -> Void

    /// Refresh only installed copies; development/test bundles must not displace the installed browser.
    static func registerInstalledCopy() {
        guard !WebProfiles.isTestMode,
              Bundle.main.bundleURL.standardizedFileURL.path == "/Applications/Ikago.app" else { return }
        let status = LSRegisterURL(Bundle.main.bundleURL as CFURL, true)
        if status != noErr { NSLog("Ikago browser registration failed (%d)", status) }
    }

    init(application: URL = Bundle.main.bundleURL,
         handler: @escaping (String) -> URL? = { $0 == "html" ? NSWorkspace.shared.urlForApplication(toOpen: .html) : NSWorkspace.shared.urlForApplication(toOpen: URL(string: "\($0)://example.invalid")!) },
         candidates: @escaping (String) -> [URL] = {
             $0 == "html" ? NSWorkspace.shared.urlsForApplications(toOpen: .html)
                 : NSWorkspace.shared.urlsForApplications(toOpen: URL(string: "\($0)://example.invalid")!)
         },
         register: @escaping (URL) throws -> Void = { application in
             guard !WebProfiles.isTestMode else { throw CocoaError(.userCancelled) }
             let status = LSRegisterURL(application as CFURL, true)
             guard status == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
         },
         request: @escaping (URL, String) async throws -> Void = { application, scheme in
             guard !WebProfiles.isTestMode else { throw CocoaError(.userCancelled) }
             if scheme == "html" {
                 try await NSWorkspace.shared.setDefaultApplication(at: application, toOpen: .html)
             } else {
                 try await NSWorkspace.shared.setDefaultApplication(at: application, toOpenURLsWithScheme: scheme)
             }
         }) {
        self.application = application; self.handler = handler; self.request = request
        self.candidates = candidates; self.register = register
        refresh()
    }
    private func owns(_ scheme: String) -> Bool {
        guard let current = handler(scheme) else { return false }
        return current.standardizedFileURL.resolvingSymlinksInPath() == application.standardizedFileURL.resolvingSymlinksInPath()
    }
    func refresh() {
        let canonical = application.standardizedFileURL.resolvingSymlinksInPath()
        isRegistered = ["http", "https", "html"].allSatisfy { scheme in
            candidates(scheme).contains { $0.standardizedFileURL.resolvingSymlinksInPath() == canonical }
        }
        isDefault = isRegistered && owns("http") && owns("https") && owns("html")
    }
    func makeDefault() async {
        guard !changing else { return }
        changing = true; message = nil
        defer { changing = false; refresh() }
        do {
            try register(application)
            for scheme in ["http", "https", "html"] where !owns(scheme) {
                try await request(application, scheme)
            }
            refresh()
            if !isDefault { message = "The default browser has not changed. You can also choose it in System Settings." }
        } catch {
            refresh()
            message = (error as NSError).code == NSUserCancelledError
                ? "The request was cancelled."
                : "Couldn’t change the default browser: \(error.localizedDescription)"
        }
    }
}

struct DefaultBrowserSection: View {
    @State private var setting = DefaultBrowserSetting()
    var body: some View {
        PageSection(title: "Default Browser", footer: setting.message ?? "Open web links from other apps here. macOS may ask you to confirm the change.") {
            PageRow(title: setting.isDefault ? "This is your default browser" : "Use this as your default browser") {
                Button(setting.changing ? "Requesting…" : setting.isDefault ? "Default Browser" : "Make Default") {
                    Task { await setting.makeDefault() }
                }
                .disabled(setting.isDefault || setting.changing)
            }
        }
        .task {
            while !Task.isCancelled {
                setting.refresh()
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in setting.refresh() }
    }
}
