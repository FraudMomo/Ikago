import SwiftUI

/// The address field's brain in every presentation (integrated field, top-bar field, the
/// floating ⌘L / ⌘T bar): ranked matches from `OmniboxEngine`,
/// inline autocompletion while typing forward, and arrow keys that preview a row in the field.
@MainActor
@Observable
final class CommandPaletteModel {
    enum Mode { case currentTab, newTab }
    typealias Suggestion = OmniboxMatch

    /// What the user typed. The field shows `query + inlineCompletion`, or `temporaryText` while
    /// a non-default row is highlighted. Real edits reset the highlight.
    var query = "" {
        didSet {
            guard query != oldValue else { return }
            edited = true; selection = query.isEmpty ? -1 : 0; temporaryText = nil; switchFocused = false; error = nil
            refreshCompletions()
        }
    }
    var selection = 0
    /// A highlighted row's text, shown in the field without replacing what was typed (Esc restores it).
    var temporaryText: String?
    /// Tab moved the keyboard onto the highlighted row's "Switch to this tab" button.
    var switchFocused = false
    /// Inline autocompletion only follows forward typing, never deletion or programmatic text.
    var allowsInline = false
    /// The page address offered on ⌘L is not a query until the user changes it.
    var edited = false
    var error: String?
    var mode: Mode = .currentTab
    let state: BrowserState
    @ObservationIgnored var onOpen: (String, Mode) -> Void = { _, _ in }
    @ObservationIgnored var onSwitch: (String) -> Void = { _ in }
    @ObservationIgnored var onDismiss: () -> Void = {}

    var completionActive = false
    var completions: [String] = []
    @ObservationIgnored var completionTask: Task<Void, Never>?
    @ObservationIgnored var completionProvider: (String, SearchEngine) async throws -> [String] = SearchSuggestions.fetch
    @ObservationIgnored var cache: (key: Int, matches: [Suggestion])?

    init(state: BrowserState) { self.state = state; observeCompletionPreferences() }

    func prepare(mode: Mode) {
        self.mode = mode
        completionActive = true
        allowsInline = false
        query = mode == .currentTab ? editableAddress : ""
        edited = false; selection = -1; temporaryText = nil; switchFocused = false
        refreshCompletions()
    }

    /// The active page's address to edit, or empty on new-tab pages (an extension's page
    /// such as Momentum, Ikago's own pages, or the homepage), where you start typing fresh.
    private var editableAddress: String {
        guard let url = state.activeTab?.url, AddressResolver.isPageURL(url) else { return "" }
        let homepage = try? AddressResolver.resolve(state.homepage, engine: state.searchEngine)
        if state.newTabMode == .homepage, let homepage, url.trimmingSuffix("/") == homepage.trimmingSuffix("/") {
            return ""
        }
        return url
    }

    /// Text typed in the field. Forward typing at the end allows inline autocompletion; deleting
    /// (including removing just the selected completion) turns it off until the next keystroke.
    func userEdited(_ text: String) {
        let base = temporaryText ?? query
        allowsInline = text.count > base.count && text.lowercased().hasPrefix(base.lowercased())
        temporaryText = nil
        if text != query { query = text } else { edited = true; selection = query.isEmpty ? -1 : 0; switchFocused = false }
    }

    /// The default match's untyped remainder, shown selected after the caret.
    var inlineCompletion: String {
        guard selection == 0, temporaryText == nil else { return "" }
        return suggestions.first?.inline ?? ""
    }

    /// ↑ ↓ move through rows without wrapping; the field previews the highlighted row.
    func moveSelection(_ delta: Int) {
        let items = suggestions
        guard !items.isEmpty else { return }
        // The on-focus list has no default row: ↑ from the first row returns to what was there.
        let floor = isZeroSuggest ? -1 : 0
        selection = min(max(floor, selection + delta), items.count - 1)
        switchFocused = false
        temporaryText = selection == floor || selection < 0 ? nil : items[selection].fill
    }

    /// Tab: onto the row's "Switch to this tab" button, then the next row. Shift+Tab goes back.
    func focusNext(forward: Bool) {
        let items = suggestions
        guard items.indices.contains(selection) else { return }
        if forward {
            if items[selection].tabID != nil && !switchFocused { switchFocused = true }
            else if selection < items.count - 1 { moveSelection(1) }
        } else if switchFocused {
            switchFocused = false
        } else {
            moveSelection(-1)
            if items.indices.contains(selection), items[selection].tabID != nil { switchFocused = true }
        }
    }

    /// Tab key (kept for callers that only know the forward direction).
    func completeSelection() { focusNext(forward: true) }

    /// Esc first restores what was typed; a second Esc closes the field.
    func cancel() {
        let floor = isZeroSuggest ? -1 : 0
        if selection != floor || temporaryText != nil || switchFocused {
            selection = floor; temporaryText = nil; switchFocused = false
        } else {
            onDismiss()
        }
    }

    func commit() {
        let items = suggestions
        if !edited, selection < 0, query.trimmingCharacters(in: .whitespaces) == state.activeTab?.url {
            onDismiss()
        } else if items.indices.contains(selection) {
            let item = items[selection]
            if switchFocused, let id = item.tabID { onSwitch(id) } else { activate(item) }
        } else if !query.trimmingCharacters(in: .whitespaces).isEmpty {
            do { onOpen(try AddressResolver.resolve(query, engine: state.searchEngine), mode) }
            catch { self.error = error.localizedDescription }
        }
    }

    func activate(_ suggestion: Suggestion) { onOpen(suggestion.url, mode) }

    func switchToTab(_ suggestion: Suggestion) { if let id = suggestion.tabID { onSwitch(id) } }

    /// Shift+Delete or × on a history row forgets that page, as in Chrome.
    @discardableResult func remove(_ suggestion: Suggestion) -> Bool {
        guard let url = suggestion.removableURL else { return false }
        let key = OmniboxURL.key(url)
        state.history.removeAll { OmniboxURL.key($0.url) == key }
        state.scheduleSave()
        let count = suggestions.count
        selection = min(selection, count - 1)
        temporaryText = selection <= 0 && !isZeroSuggest || selection < 0 ? nil : suggestions[selection].fill
        return true
    }

    func removeSelected() -> Bool {
        let items = suggestions
        guard selection > (isZeroSuggest ? -1 : 0), items.indices.contains(selection) else { return false }
        return remove(items[selection])
    }
}

extension String {
    func trimmingSuffix(_ suffix: String) -> String { hasSuffix(suffix) ? String(dropLast(suffix.count)) : self }
}
