import SwiftUI

/// Full, persistent history. The toolbar button opens the compact dropdown instead.
struct DownloadsPage: View {
    let colors: Palette
    private var center: DownloadCenter { .shared }
    var body: some View {
        PageScaffold(title: "Downloads", colors: colors, trailing: AnyView(
            HStack(spacing: 8) {
                Button("Clear History") { center.clearFinished() }.disabled(!center.items.contains { !$0.inProgress })
                Button("Open Folder") { center.revealDownloadsFolder() }
            })) {
            if center.items.isEmpty { EmptyNote(symbol: "arrow.down.circle", text: "No downloads yet") }
            else {
                PageSection(title: "Download History", footer: "Completed, cancelled and failed downloads stay here until you clear them. Clearing history keeps the files.") {
                    LazyVStack(spacing: 0) {
                        ForEach(center.items) { item in
                            DownloadRow(item: item, colors: colors)
                            PageDivider()
                        }
                    }
                }
            }
            if let error = center.historyError { Text(error).foregroundStyle(.orange) }
        }
        .animation(.ikago, value: center.items.map(\.id))
    }
}
