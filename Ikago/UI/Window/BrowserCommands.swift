import AppKit

/// Commands the SwiftUI chrome can issue; implemented by BrowserWindowController.
@MainActor
protocol BrowserCommands: AnyObject {
    func goBack()
    func goForward()
    func reloadOrStop()
    func showCommandPalette(newTab: Bool)
    func newTab()
    func toggleSidebar()
    /// The sidebar button: Full → Icons → Hidden → Full (top layouts: the tab sidebar).
    func cycleSidebar()
    func toggleDownloads()
    var downloadsPresented: Bool { get }
    func closeTab(_ id: String)
    func unloadTab(_ id: String)
    /// Closes a tab group in a top layout: no strip space, pages unloaded, reopenable.
    func closeGroup(_ id: String)
    func unloadGroup(_ id: String)
    func toggleMute(_ id: String)
    func controlMedia(_ id: String, action: MediaPlaybackAction)
    /// Mutes/resumes or ends a tab's camera or microphone capture.
    func setCaptureMuted(_ id: String, microphone: Bool, muted: Bool)
    func stopCapture(_ id: String, microphone: Bool)
    func splitWith(_ id: String)
    func showSettings()
    func openPage(_ page: InternalPage)
    func peekTab(_ id: String)
    func previewImage(_ id: String) async -> NSImage?
    func performanceTabs() -> [TabPerformanceEntry]
    func openInPrivateWindow(_ url: String)
    func openInNewTab(_ url: String)
    func openDroppedFiles(_ urls: [URL])
    func openBookmark(_ bookmark: Bookmark, forceNewTab: Bool)
    func installFromWebStore(_ id: String)
    func installLocalExtension(at url: URL)
    func installSafariExtension(at appex: URL)
    /// The tab extension actions apply to (the active one).
    var activeExtensionTab: TabController? { get }
    func newSpace()
    func renameSpace(_ id: UUID)
    func deleteSpace(_ id: UUID)
    func setSpaceShared(_ id: UUID, shared: Bool)
    func newFolder(with tabID: String?)
    func renameFolder(_ id: String)
    /// Asks for an emoji to use as the group's icon.
    func chooseFolderEmoji(_ id: String)
    func newBookmarkFolder(parentID: String?)
    func renameBookmarkFolder(_ id: String)
    func editBookmark(_ bookmark: Bookmark)
}
