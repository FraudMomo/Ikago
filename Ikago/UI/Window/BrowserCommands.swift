import AppKit

/// Commands the SwiftUI chrome can issue; implemented by BrowserWindowController.
@MainActor
protocol BrowserCommands: AnyObject {
    /// Saves the active page in `format` (asking where), or copies it; false when the person cancelled the save panel.
    func savePage(_ format: PageSaveFormat, copy: Bool) async throws -> Bool
    /// Answers the permission prompt on screen (`PermissionPrompt`).
    func finishPermission(_ choice: PermissionChoice)
    func goBack()
    func goForward()
    func reloadOrStop()
    func showCommandPalette(newTab: Bool)
    func newTab()
    func toggleSidebar()
    /// The sidebar button: Full → Icons → Hidden → Full.
    func cycleSidebar()
    /// The full sidebar, docked (from the icon rail's Expand: keep it open).
    func showFullSidebar()
    func toggleDownloads()
    var downloadsPresented: Bool { get }
    func toggleDevices()
    var devicesPresented: Bool { get }
    func closeTab(_ id: String)
    func unloadTab(_ id: String)
    func unloadGroup(_ id: String)
    /// Hides a group: saved, its pages asleep, out of the tab row until shown again.
    func hideGroup(_ id: String)
    /// Deletes a group with the groups inside it and closes their tabs, after asking when it holds more than one tab.
    func deleteGroup(_ id: String)
    func toggleMute(_ id: String)
    func pictureInPicture(_ id: String)
    func controlMedia(_ id: String, action: MediaPlaybackAction)
    /// Mutes/resumes or ends a tab's camera or microphone capture.
    func setCaptureMuted(_ id: String, microphone: Bool, muted: Bool)
    func stopCapture(_ id: String, microphone: Bool)
    func splitWith(_ id: String)
    func togglePageAssistant()
    func showSettings()
    func openPage(_ page: InternalPage)
    func showTabHover(_ id: String, anchor: CGRect)
    func hideTabHover(_ id: String)
    var peekContent: NSView? { get }
    /// The page shown in the Shift-click preview.
    var peekTab: TabItem? { get }
    func peekLink(_ url: String)
    func focusPeek()
    func closePeek()
    func openPeek()
    func peekTab(_ id: String)
    func previewImage(_ id: String) async -> NSImage?
    func performanceTabs() -> [TabPerformanceEntry]
    func openInPrivateWindow(_ url: String)
    /// Clear Browsing Data (`ClearDataSheet`).
    func showClearData()
    /// The tab, with its page, in a new window (`BrowserWindows`).
    func moveToNewWindow(_ id: String)
    /// The selected tabs when `id` is one of several (`TabClick`), else just `id`; and what their menu does with them.
    func tabSelection(including id: String) -> [String]
    func moveTabsToNewWindow(_ ids: [String])
    func closeTabs(_ ids: [String])
    func moveTabs(_ ids: [String], toFolder folderID: String?)
    func newFolder(withTabs ids: [String])
    func openInNewTab(_ url: String)
    /// Opens `url` in this tab, or a new one.
    func open(_ url: String, inNewTab: Bool)
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
    func customizeFolder(_ id: String)
    func renameFolder(_ id: String)
    /// Asks for an emoji to use as the group's icon.
    func chooseFolderEmoji(_ id: String)
    func newBookmarkFolder(parentID: String?)
    func renameBookmarkFolder(_ id: String)
    func editBookmark(_ bookmark: Bookmark)
}
