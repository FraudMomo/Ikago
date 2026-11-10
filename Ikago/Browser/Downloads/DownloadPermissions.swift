import AppKit

/// Asks before a site saves files, so a page can't drop a file into Downloads unnoticed.
/// The answer is remembered per site. Without a window to ask in, the download doesn't happen.
@MainActor
final class DownloadPermissions {
    static let shared = DownloadPermissions()
    #if DEBUG
    /// Unattended checks answer here instead of through a sheet.
    var testAnswer: Bool?
    private(set) var testPrompts = 0
    #endif
    private var pending: [String: Task<Bool, Never>] = [:]
    /// After Cancel a site can't ask again straight away, so a page can't nag in a loop.
    private var declined: [String: Date] = [:]
    private static let quietPeriod: TimeInterval = 30

    /// The site asking: the page on screen, or the file's own host when no page is open yet.
    static func site(pageURL: URL?, downloadURL: URL?) -> String {
        let host = (pageURL?.host ?? downloadURL?.host ?? "").lowercased()
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    func mayDownload(pageURL: URL?, downloadURL: URL?, state: BrowserState?, window: NSWindow?) async -> Bool {
        guard let state else { return false }
        guard state.browserPreferences.askBeforeDownloads ?? true else { return true }
        let site = Self.site(pageURL: pageURL, downloadURL: downloadURL)
        if (state.browserPreferences.downloadSites ?? []).contains(site) { return true }
        if let last = declined[site], Date().timeIntervalSince(last) < Self.quietPeriod { return false }
        if let task = pending[site] { return await task.value }
        let task = Task<Bool, Never> { @MainActor in await self.ask(site: site, window: window) }
        pending[site] = task
        let allowed = await task.value
        pending[site] = nil
        if allowed {
            state.browserPreferences.downloadSites = (state.browserPreferences.downloadSites ?? []) + [site]
        } else {
            declined[site] = Date()
        }
        return allowed
    }

    private func ask(site: String, window: NSWindow?) async -> Bool {
        #if DEBUG
        if WebProfiles.isTestMode { testPrompts += 1; return testAnswer ?? true }
        #endif
        guard let window else { return false }
        let alert = NSAlert()
        alert.messageText = site.isEmpty ? "Allow this page to download files?" : "Allow “\(site)” to download files?"
        alert.informativeText = "Files are saved to your Downloads folder. You can change this in Settings ▸ Security."
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[1].keyEquivalent = "\u{1b}"
        return await alert.beginSheetModal(for: window) == .alertFirstButtonReturn
    }

    func forgetDeclines() { declined.removeAll() }
}
