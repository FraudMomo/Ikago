import SwiftUI

struct TabPeek: View {
    let tab: TabItem
    weak var commands: BrowserCommands?
    var activate: (() -> Void)? = nil
    @State private var image: NSImage?
    @State private var subscription: UUID?
    @State private var pid: Int32?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 260).clipShape(RoundedRectangle(cornerRadius: 8))
            }
            HStack(spacing: 8) {
                FaviconView(tab: tab)
                Text(tab.displayTitle).font(.system(size: 13, weight: .semibold)).lineLimit(2)
            }
            Text(tab.addressLabel).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            HStack {
                Text(tab.engine?.rawValue.capitalized ?? "Engine chosen on load")
                Spacer()
                if tab.isHibernating { Text("Unloaded") }
                else if let pid, let process = PerformanceMonitor.shared.sample.rows.first(where: { $0.id == pid }) {
                    Text("\(PerformanceSample.bytes(process.memory)) · shared renderer")
                }
            }.font(.system(size: 10)).foregroundStyle(.secondary)
            if let activate { Button("Open Tab", action: activate).buttonStyle(.borderedProminent).controlSize(.small) }
        }
        .padding(14).frame(width: 320)
        .task {
            pid = commands?.performanceTabs().first { $0.id == tab.id }?.pid
            if !tab.isHibernating { subscription = PerformanceMonitor.shared.subscribe() }
            image = await commands?.previewImage(tab.id)
        }
        .onDisappear {
            if let subscription { PerformanceMonitor.shared.unsubscribe(subscription) }
            subscription = nil
            image = nil
        }
    }
}

/// A delayed, demand-driven preview. No page is loaded just to show this card.
private struct HoverTabPeek: ViewModifier {
    let tab: TabItem
    weak var commands: BrowserCommands?
    @State private var hovering = false
    @State private var showing = false
    @Environment(\.sidebarScrolling) private var scrolling
    func body(content: Content) -> some View {
        content
            .onHover { hovering = $0 }
            .task(id: hovering && !scrolling) {
                guard hovering && !scrolling else { showing = false; return }
                try? await Task.sleep(for: .milliseconds(750))
                guard !Task.isCancelled else { return }
                showing = true
            }
            .popover(isPresented: $showing, arrowEdge: .trailing) { TabPeek(tab: tab, commands: commands) }
    }
}

extension View {
    func tabPeek(_ tab: TabItem, commands: BrowserCommands?) -> some View { modifier(HoverTabPeek(tab: tab, commands: commands)) }
}
