import Foundation

extension CommandPaletteModel {
    /// The on-focus list is showing: nothing is highlighted until ↓, and Return keeps the page.
    var isZeroSuggest: Bool { !edited || query.isEmpty }

    /// Ranked omnibox matches for the current text, memoized per input and model revision.
    /// Reading the inputs here keeps SwiftUI observation intact.
    var suggestions: [Suggestion] {
        var hasher = Hasher()
        hasher.combine(query); hasher.combine(allowsInline); hasher.combine(edited); hasher.combine(mode == .newTab)
        let remote = state.browserPreferences.searchEngineAutocomplete == true ? completions : []
        hasher.combine(remote); hasher.combine(state.searchEngine)
        hasher.combine(state.history.count); hasher.combine(state.history.first?.url); hasher.combine(state.history.first?.time)
        hasher.combine(state.history.first?.title)
        hasher.combine(state.bookmarks.count); hasher.combine(state.bookmarks.last?.url)
        for tab in state.tabs { hasher.combine(tab.id); hasher.combine(tab.url); hasher.combine(tab.spaceID) }
        hasher.combine(state.activeTabID); hasher.combine(state.activeSpaceID)
        hasher.combine(state.browserPreferences.showSwitchToTabSuggestions); hasher.combine(state.searchShowsHistory)
        let key = hasher.finalize()
        if let cache, cache.key == key { return cache.matches }
        // Focusing the field (empty, or the untouched page address) lists recent searches and top pages.
        let input = OmniboxInput(query, engine: state.searchEngine, allowsInline: allowsInline)
        let matches = OmniboxEngine(state: state).matches(for: input, remote: remote, zeroSuggest: isZeroSuggest)
        cache = (key, matches)
        return matches
    }
}
