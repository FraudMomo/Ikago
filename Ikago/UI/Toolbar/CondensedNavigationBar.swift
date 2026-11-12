import SwiftUI

/// A quiet page-title ribbon while reading; controls and tab titles return on demand.
struct CondensedNavigationBar: View {
    let state: BrowserState
    let chrome: ChromeModel
    weak var commands: BrowserCommands?
    var body: some View {
        HStack(spacing: 10) {
            if !state.barAtBottom { Color.clear.frame(width: 76) }
            ChromeButton(symbol: "chevron.left", help: "Back", colors: state.barPalette, size: 26, enabled: state.activeTab?.canGoBack == true) { commands?.goBack() }
            Button { state.barCondensed = false } label: {
                HStack(spacing: 7) {
                    if let tab = state.activeTab { FaviconView(tab: tab, size: 12) }
                    Text(state.activeTab?.displayTitle ?? "Ikago").lineLimit(1).font(.system(size: 12, weight: .medium))
                    Image(systemName: state.barAtBottom ? "chevron.up" : "chevron.down").font(.system(size: 8))
                }.frame(maxWidth: .infinity).contentShape(Rectangle())
            }.buttonStyle(.plain).help("Expand navigation")
            ChromeButton(symbol: "square.on.square", help: "Show tabs", colors: state.barPalette, size: 26) {
                state.barCondensed = false
                chrome.showTabOverview = true
            }
        }
        .padding(.horizontal, 12).frame(height: 36)
        .background(WindowDragArea())
    }
}
