import WebKit

/// Clearing browsing data (Settings ▸ Privacy, and "clear when quitting").
extension BrowserState {
    var clearsDataOnQuit: Bool { browserPreferences.clearDataOnQuit == true && !isPrivate }

    /// Forgets history, recently closed tabs, cached favicons and every Space's website data
    /// (cookies, logins, storage). Open tabs, bookmarks and settings stay.
    func clearBrowsingData() async {
        let knownURLs = history.map(\.url) + tabs.map(\.url)
        history.removeAll()
        closed.removeAll()
        FaviconCache.shared.clear()
        for profileID in Set(spaces.map(\.profileID)) {
            // A Chromium clear that fails finishes on the next launch, so "clear when quitting" can't leave data behind.
            do { try await EngineCookieSync.clearBothEngines(profile: profileID, knownURLs: knownURLs) }
            catch { NSLog("Ikago: Chromium data not cleared for a Space, retrying next launch: %@", error.localizedDescription) }
        }
        DownloadCenter.shared.clearFinished()  // the list and its source URLs; never the files
        saveNow()
        store.discardBackup()
    }
}
