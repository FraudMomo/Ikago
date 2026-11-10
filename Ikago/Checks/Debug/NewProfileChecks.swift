#if DEBUG
import Foundation

/// A new profile's defaults, the welcome page's place among internal pages, and Settings search. Part of `featurechecks`.
@MainActor
enum NewProfileChecks {
    static func run(_ check: (Bool, String) -> Void) {
        let directory = FileManager.default.temporaryDirectory.appending(path: "IkagoNewProfile-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SessionStore(directory: directory)
        let state = BrowserState(store: store)
        check(!BrowserState.isRealProfile(store) && !state.pendingWelcome, "check profiles keep the built-in defaults")

        state.applyNewProfileDefaults()
        let prefs = state.browserPreferences
        check(state.tabLayout == .vertical && state.frameInset == 2 && state.sidebarGap == 3 && !state.useGlass
              && prefs.translucentSidebar == true && prefs.sidebarCompact == nil, "new profiles start with the docked sidebar look")
        check(state.groupLabelStyle == .colorPill && !state.showsGroupTabCounts && state.tabHighlightStyle == .none
              && prefs.instantTabSwitching == true, "new profiles use color pills, no counts and instant switching")
        check(prefs.preferredEngine == BrowserState.newProfileEngine && prefs.chromiumVideoTranslation == false
              && prefs.chromiumLiveWave == nil, "new profiles start on Chromium with media extras off")
        check(state.searchEngine == .google && state.addressStyle == .floating && !state.showsBookmarksBar && state.showsPinnedGrid,
              "new profiles search with Google from the floating bar")
        check(state.chromeLayout.sidebarTop == [.sidebarToggle, .back, .forward]
              && state.chromeLayout.sidebarBottom == [.spaces, .newSpace, .settings], "new profiles get the clean sidebar controls")
        state.saveNow()
        let restored = BrowserState(store: store)
        check(restored.frameInset == 2 && restored.groupLabelStyle == .colorPill && restored.browserPreferences.preferredEngine == .chromium,
              "new-profile defaults are saved as the profile's own values")

        check(InternalPage(url: "ikago://welcome") == .welcome && !BrowserState.isReopenableInternalPage(InternalPage.welcome.url),
              "the welcome page opens from ikago://welcome and isn't reopened")
        check(SettingsSearch.results(for: "https").first?.title == "Always require HTTPS"
              && SettingsSearch.results(for: "translate x").contains { $0.category == .general }
              && SettingsSearch.results(for: "zzzz").isEmpty, "Settings search finds settings by title and keyword")
        check(Set(SettingsSearch.index.map(\.id)).count == SettingsSearch.index.count, "Settings search entries are unique")
    }
}
#endif
