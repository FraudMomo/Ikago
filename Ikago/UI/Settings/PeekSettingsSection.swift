import SwiftUI

/// Settings ▸ Tabs ▸ Peek: when a clicked link opens in Peek (`LinkPeek`, `BrowserState.peeks`).
struct PeekSettingsSection: View {
    @Bindable var state: BrowserState

    var body: some View {
        let mode = state.browserPreferences.linkPeek ?? .shiftClick
        PageSection(title: "Peek", footer: "Peek shows a link in a large card over the window. Keep it as a tab or close it.") {
            PageRow(title: "Open links in Peek", subtitle: mode.summary) {
                SettingsSegmented(selection: Binding(get: { mode }, set: { state.browserPreferences.linkPeek = $0 == .shiftClick ? nil : $0 }), options: LinkPeek.allCases.map { ($0, $0.title) })
            }
            if mode == .automatic {
                PageDivider()
                toggle("Links to other sites from pinned tabs", subtitle: "Your pinned app stays where it is",
                       get: state.browserPreferences.peekPinnedLinks != false) { state.browserPreferences.peekPinnedLinks = $0 ? nil : false }
                PageDivider()
                toggle("Results from a search page", subtitle: "Look through results without losing the list",
                       get: state.browserPreferences.peekSearchResults != false) { state.browserPreferences.peekSearchResults = $0 ? nil : false }
                PageDivider()
                toggle("Links that would open a new tab", subtitle: "Instead of a new tab, until you keep it",
                       get: state.browserPreferences.peekNewTabLinks == true) { state.browserPreferences.peekNewTabLinks = $0 ? true : nil }
            }
        }
        .animation(.ikago, value: mode)
    }

    private func toggle(_ title: String, subtitle: String, get: Bool, set: @escaping (Bool) -> Void) -> some View {
        PageRow(title: title, subtitle: subtitle) {
            Toggle(title, isOn: Binding(get: { get }, set: set)).labelsHidden().toggleStyle(.switch)
        }
    }
}

extension LinkPeek {
    var summary: String {
        switch self {
        case .off: "Links never open in Peek; Shift-click opens a new tab"
        case .shiftClick: "Shift-click a link to peek at it"
        case .automatic: "Shift-click, and the links you choose below"
        }
    }
}
