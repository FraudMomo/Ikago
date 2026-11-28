import AppKit
import SwiftUI

/// Says what macOS is about to ask before it asks, during an import: a card in the frontmost window, never a Finder
/// window or a trip to System Settings out of the blue. Two cases: macOS's folder window, where one click allows
/// Ikago to read a browser's data (`BrowserImportAccess`), and Full Disk Access, the only way to Safari's logins and
/// open tabs.
@MainActor @Observable
final class ImportAccessPrompt {
    static let shared = ImportAccessPrompt()

    enum Kind: Equatable {
        /// macOS's folder window comes next, open on the browser's folder.
        case folder(browser: String, folder: String)
        /// Safari's logins and open tabs need Full Disk Access, in System Settings.
        case fullDiskAccess(browser: String)
    }

    private(set) var kind: Kind?
    @ObservationIgnored private var answer: CheckedContinuation<Bool, Never>?

    /// Shows the card and waits: true to go on (to the folder window, or to System Settings), false for Not Now.
    func ask(_ kind: Kind) async -> Bool {
        answer?.resume(returning: false)
        return await withCheckedContinuation { continuation in
            answer = continuation
            withAnimation(.ikago) { self.kind = kind }
        }
    }

    func finish(_ goOn: Bool) {
        withAnimation(.ikago) { kind = nil }
        answer?.resume(returning: goOn)
        answer = nil
    }

    static func openFullDiskAccess() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") { NSWorkspace.shared.open(url) }
    }

    #if DEBUG
    /// Shows the card without waiting for an answer (screenshots).
    func showForCheck(_ kind: Kind?) { withAnimation(.ikago) { self.kind = kind } }
    #endif
}

struct ImportAccessSheet: View {
    let prompt: ImportAccessPrompt
    let kind: ImportAccessPrompt.Kind
    let colors: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon).font(.system(size: 22, weight: .medium)).foregroundStyle(colors.accent)
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(colors.accent.opacity(0.12)))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(colors.text)
                    Text(message).font(.system(size: 12.5)).foregroundStyle(colors.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(index + 1)").font(.system(size: 11, weight: .semibold)).foregroundStyle(colors.secondary)
                            .frame(width: 18, height: 18).background(Circle().fill(colors.hover.opacity(2)))
                        Text(step).font(.system(size: 12.5)).foregroundStyle(colors.text).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(colors.hover))
            Text("Ikago only reads this data to import it, on this Mac. Nothing is sent anywhere.")
                .font(.system(size: 11.5)).foregroundStyle(colors.tertiary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Spacer()
                Button("Not Now") { prompt.finish(false) }.buttonStyle(ModalButtonStyle(colors: colors))
                    .keyboardShortcut(.cancelAction)
                Button(action) { prompt.finish(true) }.buttonStyle(ModalButtonStyle(colors: colors, primary: true))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .modalCard(colors, width: 420)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private var icon: String {
        if case .fullDiskAccess = kind { "lock.shield" } else { "folder.badge.person.crop" }
    }
    private var title: String {
        switch kind {
        case .folder(let browser, _): "Allow Ikago to read \(browser)’s data"
        case .fullDiskAccess(let browser): "\(browser)’s logins and open tabs need Full Disk Access"
        }
    }
    private var message: String {
        switch kind {
        case .folder(let browser, _):
            "macOS keeps each app’s data private. To import your bookmarks, history, tabs and logins from \(browser), "
                + "macOS asks you to allow it once, in a folder window."
        case .fullDiskAccess(let browser):
            "Everything else from \(browser) is imported. macOS keeps its logins and open tabs behind Full Disk Access, "
                + "which only you can turn on, in System Settings."
        }
    }
    private var steps: [String] {
        switch kind {
        case .folder(let browser, let folder):
            ["A folder window opens with \(browser)’s folder, “\(folder)”, already chosen.",
             "Click Allow Import. macOS remembers it, so you won’t be asked again."]
        case .fullDiskAccess:
            ["In System Settings, turn on Ikago under Full Disk Access.",
             "Quit and reopen Ikago when macOS asks, then import again."]
        }
    }
    private var action: String {
        if case .fullDiskAccess = kind { "Open System Settings" } else { "Continue" }
    }
}
