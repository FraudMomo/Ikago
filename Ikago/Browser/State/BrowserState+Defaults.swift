import Foundation

/// How a brand-new profile starts. Saved profiles keep their own choices: these values are written once, when there is
/// no session yet, so changing them never alters an existing profile. Unattended checks keep the built-in defaults.
extension BrowserState {
    /// The engine a new profile starts on. The welcome page (`InternalPage.welcome`) asks before any site loads.
    static let newProfileEngine = BrowserEngine.chromium

    /// The person's own profile, not a check run's disposable one.
    static func isRealProfile(_ store: SessionStore) -> Bool {
        EngineCookieSync.usesRealStores && store.directory == SessionStore.standard.directory
    }

    func applyNewProfileDefaults() {
        tabLayout = .vertical
        sidebarVisible = true
        frameInset = 2
        sidebarGap = 3
        useGlass = false
        addressStyle = .floating
        searchEngine = .google
        groupLabelStyle = .colorPill
        showsGroupTabCounts = false
        tabHighlightStyle = .none
        showsBookmarksBar = false
        browserPreferences.translucentSidebar = true
        browserPreferences.sidebarCompact = nil
        browserPreferences.instantTabSwitching = true
        browserPreferences.showPinnedGrid = true
        browserPreferences.preferredEngine = Self.newProfileEngine
        browserPreferences.chromiumVideoTranslation = false
        browserPreferences.chromiumLiveWave = nil
        chromeLayout.sidebarTop = [.sidebarToggle, .back, .forward]
        chromeLayout.sidebarBottom = [.spaces, .newSpace, .settings]
    }
}
