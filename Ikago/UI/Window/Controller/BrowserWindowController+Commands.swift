import AppKit
import SwiftUI

/// Menu / keyboard actions. They travel the responder chain (window → this controller),
/// so the same selectors work whether focus is in SwiftUI, an overlay or a web view.
extension BrowserWindowController: BrowserCommands, NSMenuItemValidation {
    // MARK: BrowserCommands

    func goBack() { activeController?.goBack() }
    func goForward() { activeController?.goForward() }

    func reloadOrStop() {
        guard let tab = state.activeTab, let page = activeController?.page else { return }
        if tab.isLoading { page.stopLoading() } else { page.reload() }
    }

    var downloadsPresented: Bool { chrome.showDownloads }
    func toggleDownloads() {
        withAnimation(.ikagoQuick) { chrome.showDownloads.toggle() }
    }
    var devicesPresented: Bool { chrome.showDevices }
    func toggleDevices() {
        withAnimation(.ikagoQuick) { chrome.showDevices.toggle() }
    }
    func toggleSidebar() {
        guard state.webApp == nil else { return }
        chrome.showDownloads = false
        chrome.peeking = false
        withAnimation(.ikago) { state.sidebarVisible.toggle() }
    }

    func closeTab(_ id: String) {
        if findPanel(isFor: id) { closeFindBar() }
        state.closeTab(id)
        if state.tab(id)?.pinned == true { content.controller(for: id)?.hibernate() }
        // As in Chrome, a window closes with its last tab while another window is open (the first window then takes
        // over another one's tabs, `BrowserWindows.handOver`).
        if state.tabs.isEmpty, state.primary != nil || (BrowserWindows.primary === self && !BrowserWindows.others.isEmpty) {
            window?.performClose(nil)
        }
    }

    func unloadTab(_ id: String) {
        guard let released = state.unloadTab(id) else { return }
        content.controller(for: released)?.hibernate()
    }

    func unloadGroup(_ id: String) {
        for member in state.unloadFolder(id) { content.controller(for: member)?.hibernate() }
    }

    /// Tab ▸ Reopen Closed Group.
    @objc func reopenGroup(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        state.reopenFolder(id)
    }

    func setCaptureMuted(_ id: String, microphone: Bool, muted: Bool) {
        content.controller(for: id)?.page?.setCaptureMuted(muted, microphone: microphone)
    }

    func stopCapture(_ id: String, microphone: Bool) {
        content.controller(for: id)?.page?.stopCapture(camera: !microphone, microphone: microphone)
    }

    func toggleMute(_ id: String) {
        guard let tab = state.tab(id) else { return }
        tab.isMuted.toggle()
        content.controller(for: id)?.page?.setMuted(tab.isMuted)
    }

    func splitWith(_ id: String) { state.splitActive(with: id) }

    func openInNewTab(_ url: String) {
        openTabForExtension(url: url, active: true, pinned: false, useNewTabPosition: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Bookmarks ▸ a bookmark (`BookmarksMenu`). ⌘-click opens it in a new tab.
    @objc func openBookmarkFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let bookmark = state.bookmarks.first(where: { $0.id == id }) else { return }
        openBookmark(bookmark, forceNewTab: NSEvent.modifierFlags.contains(.command))
    }

    func openBookmark(_ bookmark: Bookmark, forceNewTab: Bool = false) {
        dismissCommandPalette()
        chrome.showDownloads = false
        withAnimation(.ikago) { _ = state.openBookmark(bookmark, forceNewTab: forceNewTab) }
        window?.makeKeyAndOrderFront(nil)
    }

    var activeExtensionTab: TabController? { activeController }

    // MARK: Extensions

    func installFromWebStore(_ id: String) {
        Task { await installFromWebStore(id: id) }
    }

    /// Downloads, asks the user, installs. Returns whether the extension ended up installed.
    @discardableResult
    func installFromWebStore(id: String) async -> Bool {
        do {
            let folder = try await WebStoreInstaller.download(id: id)
            defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
            return try await ExtensionManager.shared.install(unpackedAt: folder, id: id, fromWebStore: true)
        } catch {
            ExtensionManager.shared.installIssue = error.localizedDescription
            presentError(error, title: "Couldn't add the extension")
            return false
        }
    }

    func installLocalExtension(at url: URL) {
        Task {
            do {
                var folder = url
                if !url.hasDirectoryPath {
                    folder = try WebStoreInstaller.unpack(packageData: try Data(contentsOf: url))
                } else {
                    let copy = FileManager.default.temporaryDirectory.appending(path: "ikago-ext-\(UUID().uuidString)")
                    try FileManager.default.copyItem(at: url, to: copy)
                    folder = copy
                }
                try await ExtensionManager.shared.install(unpackedAt: folder, id: WebStoreInstaller.localID(for: url),
                                                          fromWebStore: false)
            } catch {
                ExtensionManager.shared.installIssue = error.localizedDescription
            presentError(error, title: "Couldn't add the extension")
            }
        }
    }

    func installSafariExtension(at appex: URL) {
        Task {
            do { try await ExtensionManager.shared.installSafariExtension(at: appex) } catch {
                ExtensionManager.shared.installIssue = error.localizedDescription
            presentError(error, title: "Couldn't add the extension")
            }
        }
    }

    private func presentError(_ error: Error, title: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        if let window, window.attachedSheet == nil { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }

    private func findPanel(isFor id: String) -> Bool { id == state.activeTabID }

    // MARK: Menu actions

    @objc func newTab(_ sender: Any?) { newTab() }
    @objc func openLocation(_ sender: Any?) { showCommandPalette(newTab: false) }
    @objc func closeCurrentTab(_ sender: Any?) {
        if state.webApp != nil { return window?.performClose(sender) ?? () }
        if let id = state.activeTabID { closeTab(id) } else { window?.performClose(sender) }
    }
    /// Chrome's ⌘⇧T: whatever closed last, one of this window's tabs or a whole window.
    @objc func reopenClosedTab(_ sender: Any?) {
        if state.reopensWindowNext, BrowserWindows.reopenClosedWindow() { return }
        state.reopenClosedTab()
    }
    @objc func stopLoadingPage(_ sender: Any?) { activeController?.page?.stopLoading() }
    @objc func reloadPage(_ sender: Any?) { activeController?.page?.reload() }
    @objc func hardReloadPage(_ sender: Any?) { activeController?.page?.reloadIgnoringCache() }
    @objc func navigateBack(_ sender: Any?) { goBack() }
    @objc func navigateForward(_ sender: Any?) { goForward() }
    @objc func toggleIkagoSidebar(_ sender: Any?) { toggleSidebar() }
    func cycleSidebar() {
        chrome.showDownloads = false
        chrome.peeking = false
        withAnimation(.ikago) {
            // Sidebar + Tabs has no full sidebar: the button shows and hides the rail.
            if state.usesTabsLayout {
                state.sidebarVisible.toggle()
            } else if !state.sidebarVisible {
                state.browserPreferences.sidebarCompact = nil
                state.sidebarVisible = true
            } else if state.showsSidebarRail {
                state.sidebarVisible = false
            } else {
                state.browserPreferences.sidebarCompact = true
            }
        }
    }

    /// Sidebar layout: the full sidebar or its rail of icons. A hidden sidebar comes back in the chosen form.
    @objc func toggleCompactSidebar(_ sender: Any?) {
        chrome.peeking = false
        let compact = state.showsSidebarRail
        if state.usesTabsLayout { return toggleSidebar() }
        withAnimation(.ikago) {
            state.browserPreferences.sidebarCompact = compact ? nil : true
            state.sidebarVisible = true
        }
    }
    @objc func findInPage(_ sender: Any?) { showFindBar() }
    @objc func findNextMatch(_ sender: Any?) { find.search(forward: true, next: true) }
    @objc func findPreviousMatch(_ sender: Any?) { find.search(forward: false, next: true) }
    @objc func printCurrentPage(_ sender: Any?) { activeController?.page?.printPage() }
    @objc func toggleReader(_ sender: Any?) { activeController?.toggleReader() }
    @objc func savePageAs(_ sender: Any?) {
        guard let page = activeController?.page, let tab = state.activeTab else { return }
        PageSaver.save(page, title: tab.title, in: window)
    }
    @objc func nextTab(_ sender: Any?) { state.selectAdjacent(1) }
    @objc func previousTab(_ sender: Any?) { state.selectAdjacent(-1) }
    /// Cmd+1…8 select by position, Cmd+9 selects the last tab (Chrome convention).
    @objc func selectTabByNumber(_ sender: NSMenuItem) { state.selectTab(at: sender.tag == 9 ? -1 : sender.tag - 1) }
    @objc func splitView(_ sender: Any?) { state.splitActive() }
    @objc func unsplitView(_ sender: Any?) { state.unsplit() }
    @objc func toggleSplitOrientation(_ sender: Any?) { state.toggleSplitOrientation() }
    @objc func togglePinTab(_ sender: Any?) { if let id = state.activeTabID { state.togglePin(id) } }
    @objc func toggleMuteTab(_ sender: Any?) { if let id = state.activeTabID { toggleMute(id) } }
    @objc func copyPageAddress(_ sender: Any?) {
        guard let url = state.activeTab?.url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
    }
    @objc func zoomInPage(_ sender: Any?) { adjustZoom(+1) }
    @objc func zoomOutPage(_ sender: Any?) { adjustZoom(-1) }
    @objc func resetPageZoom(_ sender: Any?) { activeController?.page?.zoomLevel = 0 }
    @objc func showDownloads(_ sender: Any?) { toggleDownloads() }
    @objc func toggleDevTools(_ sender: Any?) {
        guard state.developerTools else { return }
        activeController?.page?.toggleInspector()
    }
    @objc func bookmarkPage(_ sender: Any?) { if let tab = state.activeTab { state.addBookmark(tab) } }
    @objc func showBookmarks(_ sender: Any?) { openPage(.bookmarks) }
    @objc func showHistory(_ sender: Any?) { openPage(.history) }
    @objc func showNotes(_ sender: Any?) { openPage(.notes) }
    @objc func showIkagoSettings(_ sender: Any?) { showSettings() }
    @objc func selectColorMode(_ sender: NSMenuItem) {
        if let mode = ColorMode.allCases[safe: sender.tag] { withAnimation(.ikago) { state.colorMode = mode } }
    }

    /// One 10 % step (`PageZoom`).
    private func adjustZoom(_ direction: Int) {
        guard let page = activeController?.page else { return }
        page.zoomPercent = PageZoom.stepped(page.zoomPercent, by: direction)
    }

    // MARK: Validation

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        let tab = state.activeTab
        switch item.action {
        case #selector(toggleReader(_:)):
            item.title = activeController?.isReading == true ? "Hide Reader" : "Show Reader"
            return activeController?.isStarted == true && AddressResolver.isWebURL(activeController?.page?.currentURL ?? "")
        case #selector(installWebApp(_:)):
            return state.webApp == nil && !state.isPrivate && AddressResolver.isWebURL(activeController?.page?.currentURL ?? "")
        case #selector(translatePage(_:)):
            item.title = activeController?.translation != nil ? "Show Original" : "Translate Page"
            return activeController?.isStarted == true && AddressResolver.isWebURL(activeController?.page?.currentURL ?? "")
        case #selector(askThisPage(_:)): return state.browserPreferences.pageIntelligence == true
        case #selector(togglePerformanceStats(_:)):
            item.state = showsPerformanceStats ? .on : .off
            return true
        case #selector(toggleBookmarksBar(_:)):
            item.title = state.showsBookmarksBar ? "Hide Bookmarks Bar" : "Show Bookmarks Bar"
            return true
        case #selector(bookmarkPage(_:)):
            let saved = state.bookmarks.contains { $0.url == tab?.url }
            item.title = saved ? "Page Bookmarked" : "Bookmark This Page"
            return !saved && tab.map { AddressResolver.isWebURL($0.url) } == true
        case #selector(navigateBack(_:)): return tab?.canGoBack == true
        case #selector(stopLoadingPage(_:)): return tab?.isLoading == true
        case #selector(navigateForward(_:)): return tab?.canGoForward == true
        case #selector(reopenClosedTab(_:)): return !state.closed.isEmpty || (!state.isPrivate && !(state.primary ?? state).closedWindows.isEmpty)
        case #selector(moveTabToNewWindow(_:)): return state.activeTabID.map { BrowserWindows.canMoveOut($0, from: self) } == true
        case #selector(unsplitView(_:)), #selector(toggleSplitOrientation(_:)): return state.visibleTabIDs.count > 1
        case #selector(splitView(_:)): return tab != nil && state.visibleTabIDs.count < 4
        case #selector(toggleCompactSidebar(_:)):
            item.title = state.showsSidebarRail ? "Expand Sidebar" : "Compact Sidebar"
            return !state.usesTabsLayout
        case #selector(toggleIkagoSidebar(_:)):
            item.title = state.sidebarVisible ? "Hide Sidebar" : "Show Sidebar"
            return true
        case #selector(togglePinTab(_:)):
            item.title = tab?.pinned == true ? "Unpin Tab" : "Pin Tab"
            return tab != nil
        case #selector(toggleMuteTab(_:)):
            item.title = tab?.isMuted == true ? "Unmute Tab" : "Mute Tab"
            return tab != nil
        case #selector(toggleDevTools(_:)):
            item.state = activeController?.page?.isInspectorVisible == true ? .on : .off
            return state.developerTools && activeController?.page != nil
        case #selector(selectColorMode(_:)):
            item.state = ColorMode.allCases[safe: item.tag] == state.colorMode ? .on : .off
            return true
        case #selector(reloadPage(_:)), #selector(hardReloadPage(_:)), #selector(findInPage(_:)),
             #selector(findNextMatch(_:)), #selector(findPreviousMatch(_:)), #selector(printCurrentPage(_:)), #selector(savePageAs(_:)),
             #selector(copyPageAddress(_:)), #selector(zoomInPage(_:)), #selector(zoomOutPage(_:)),
             #selector(resetPageZoom(_:)):
            return activeController?.isStarted == true
        default: return true
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
