import SwiftUI

/// ikago://history: the history list (`HistoryBrowser`), as Settings ▸ History shows it too.
struct HistoryPage: View {
    let state: BrowserState
    weak var commands: BrowserCommands?

    var body: some View {
        PageScaffold(title: "History", colors: state.palette) {
            HistoryBrowser(state: state, commands: commands)
        }
    }
}

struct EmptyNote: View {
    let symbol: String
    let text: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 28, weight: .light))
            Text(text)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, minHeight: 240)
    }
}
