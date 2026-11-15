import AppKit
import Foundation

// MARK: - TabItem
/// Tab identity and metadata persist; live page contents do not. Restored pages start lazily.
@MainActor
@Observable
final class TabItem: Identifiable {
    let id: String
    var url: String
    var title: String
    var pinned: Bool
    /// Keep this pin in the sidebar list instead of its favorites grid.
    var pinAsRow = false
    /// Standalone row follows this group; nil places it above the groups.
    var pinAfterFolderID: String?
    var spaceID: UUID
    var folderID: String?

    // Live state, except the unloaded marker and favicon URL saved below.
    var shouldStartInBackground = false
    /// The tab whose link opened this one, until the person selects some other tab (Chrome's opener): closing this tab
    /// then goes back to it. Not saved.
    @ObservationIgnored var openerID: String?
    /// Back history to restore when the page next starts, and kept current while it runs (`TabHistory`).
    @ObservationIgnored var history: TabHistory?
    var faviconURL: URL?
    /// The page's <meta name="theme-color"> (WebKit's `themeColor`), used to tint the top bar.
    var themeColor: NSColor?
    var hasLivePage = false
    var isUnloaded: Bool { isHibernating || (!hasLivePage && InternalPage(url: url) == nil) }
    var isHibernating = false
    /// The engine showing this tab's page now (per-site engines can differ from the default).
    var engine: BrowserEngine?
    var isLoading = false
    var progress: Double = 0
    var canGoBack = false
    var canGoForward = false
    var isMuted = false
    var isPlayingAudio = false
    var playback = MediaPlaybackState()
    /// The page holds the camera / microphone (capturing or muted); `…Muted` while muted.
    var cameraActive = false
    var microphoneActive = false
    var cameraMuted = false
    var microphoneMuted = false
    /// A pinned tab's page changed its title while in the background (a new message, a finished job):
    var loadError: String?
    /// WebKit's `hasOnlySecureContent`: false when an HTTPS page also loaded HTTP content.
    var hasOnlySecureContent = true

    init(id: String = UUID().uuidString, url: String, title: String = "", pinned: Bool = false,
         spaceID: UUID = SpaceProfile.defaultSpace.id, folderID: String? = nil) {
        self.id = id
        self.url = InternalPage(url: url)?.url ?? url
        self.title = title
        self.pinned = pinned
        self.spaceID = spaceID
        self.folderID = folderID
    }

    var displayTitle: String {
        if let page = InternalPage(url: url) { return page.title }
        if !title.isEmpty { return title }
        if AddressResolver.isLocalFileURL(url), let file = URL(string: url) { return file.lastPathComponent }
        return AddressResolver.hostname(url).isEmpty ? "New Tab" : AddressResolver.hostname(url)
    }

    /// What the address field shows: the site, or the title for Ikago and extension pages.
    var addressLabel: String {
        if let page = InternalPage(url: url) { return page.title }
        if ExtensionURL.isExtension(url) { return displayTitle }
        let host = AddressResolver.hostname(url)
        return host.isEmpty ? displayTitle : host
    }

    var saved: SavedTab {
        SavedTab(id: id, url: url, title: title, pinned: pinned, space: spaceID.uuidString, folder: folderID, favicon: faviconURL?.absoluteString, unloaded: isHibernating, pinAsRow: pinAsRow, pinAfterFolderID: pinAfterFolderID, history: history?.isEmpty == false ? history : nil)
    }
}

/// On-disk tab record in `session.json`.
struct SavedTab: Codable, Equatable {
    var id: String
    var url: String
    var title: String
    var pinned: Bool
    // Later additions (absent in older sessions).
    var space: String? = nil
    var folder: String? = nil
    var favicon: String? = nil
    var unloaded: Bool? = nil
    var pinAsRow: Bool? = nil
    var pinAfterFolderID: String? = nil
    /// Closed tabs only: the tab it followed in its Space, so ⌘⇧T puts it back in its place.
    var after: String? = nil
    var history: TabHistory? = nil
}

struct Visit: Codable, Equatable {
    var url: String
    var title: String
    var time: UInt64  // milliseconds since 1970, as written by older sessions
    /// Omnibox ranking, like Chromium's visit_count and typed_count. Optional so older profiles restore.
    var visits: Int? = nil
    var typed: Int? = nil
}

// MARK: - TabHistory
/// A tab's Back history, kept with the session (and with recently closed tabs) so it survives relaunch, unloading and
/// ⌘⇧T. WebKit's own `interactionState` restores everything (Back and Forward, scroll positions); every
/// engine also records the addresses behind the page, which is what a Chromium page (or a page that changed engine)
/// goes back through. Bounded: a few recent entries, and a WebKit state that fits in `maxState`.
struct TabHistory: Codable, Equatable {
    /// WebKit's `interactionState`, base64.
    var state: String? = nil
    /// The pages behind the current one, oldest first.
    var back: [String]? = nil
    /// The page this history leads up to. A page starting somewhere else (a tab that navigated to another address,
    /// or swapped its view for another engine or an extension's configuration) doesn't take it.
    var url: String? = nil

    static let maxBack = 12
    static let maxState = 32 * 1024

    /// Only web addresses, a few of the latest, each a sane length.
    static func trimmed(_ urls: [String]) -> [String]? {
        let kept = urls.filter { AddressResolver.isWebURL($0) && $0.utf8.count <= 2048 }.suffix(maxBack)
        return kept.isEmpty ? nil : Array(kept)
    }

    var isEmpty: Bool { state == nil && (back ?? []).isEmpty }

    /// Whether a page starting at `destination` should take this history.
    func leads(to destination: String) -> Bool { url == nil || url == destination }
}

// MARK: - TabPerformanceEntry
struct TabPerformanceEntry: Identifiable {
    let id: String
    let title: String
    let engine: String
    let status: String
    let pid: Int32?
    let parked: Int
}
