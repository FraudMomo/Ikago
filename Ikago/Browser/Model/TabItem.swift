import AppKit
import Foundation

/// One browsing tab. The core persisted fields are id, url, title and pinned;
/// the rest is live state reported by WebKit and never written to disk.
@MainActor
@Observable
final class TabItem: Identifiable {
    let id: String
    var url: String
    var title: String
    var pinned: Bool
    var spaceID: UUID
    var folderID: String?

    // Live state (not persisted).
    var shouldStartInBackground = false
    var faviconURL: URL?
    /// The page's <meta name="theme-color"> (WebKit's `themeColor`), used to tint the top bar.
    var themeColor: NSColor?
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
        SavedTab(id: id, url: url, title: title, pinned: pinned, space: spaceID.uuidString, folder: folderID, favicon: faviconURL?.absoluteString, unloaded: isHibernating)
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
}

struct Visit: Codable, Equatable {
    var url: String
    var title: String
    var time: UInt64  // milliseconds since 1970, as written by older sessions
    /// Omnibox ranking, like Chromium's visit_count and typed_count. Optional so older profiles restore.
    var visits: Int? = nil
    var typed: Int? = nil
}
