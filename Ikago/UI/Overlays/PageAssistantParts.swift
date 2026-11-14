import SwiftUI

/// The page a message is about: its icon, title and site.
struct AssistantPageChip: View {
    let tab: TabItem
    let colors: Palette
    let fill: Color

    var body: some View {
        HStack(spacing: 9) {
            FaviconView(tab: tab, size: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(tab.displayTitle).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                Text(tab.addressLabel).font(.system(size: 11.5)).foregroundStyle(colors.secondary).lineLimit(1)
            }
            .frame(maxWidth: 190, alignment: .leading)
            .fixedSize(horizontal: true, vertical: false)  // hugs short titles, truncates long ones at 190 pt
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(fill))
    }
}

struct AssistantSuggestionRow: View {
    let title: String
    let symbol: String
    let colors: Palette
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 12)).frame(width: 16).foregroundStyle(colors.secondary)
                Text(title).font(.system(size: 13))
                Spacer()
            }
            .padding(.horizontal, 8).frame(height: 32).contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(colors.hover.opacity(hovering ? 1.4 : 0)))
        }
        .buttonStyle(.plain).onHover { hovering = $0 }
    }
}

struct PageIntelligenceSection: View {
    let state: BrowserState
    var body: some View {
        PageSection(title: "Apple Intelligence", footer: "Reads a page excerpt only when you ask. Processing stays on this Mac.") {
            PageRow(title: "Page assistance", subtitle: "Summarize and ask questions about a page") {
                Toggle("Page assistance", isOn: Binding(get: { state.browserPreferences.pageIntelligence == true }, set: { state.browserPreferences.pageIntelligence = $0 }))
                    .labelsHidden().toggleStyle(.switch)
            }
            if let issue = PageAssistantModel.availability {
                PageDivider()
                PageRow(title: "Availability", subtitle: issue) { EmptyView() }
            }
        }
    }
}
