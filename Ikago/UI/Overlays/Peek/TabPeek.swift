import SwiftUI

/// The small card that appears after resting on a tab: the page's title and site, an optional thumbnail, and how much
/// memory its renderer uses. Settings ▸ Tabs ▸ Tab Previews turns it, or just the thumbnail, off.
struct TabPeek: View {
    let tab: TabItem
    weak var commands: BrowserCommands?
    var activate: (() -> Void)? = nil
    @State private var image: NSImage?
    init(tab: TabItem, commands: BrowserCommands?, image: NSImage? = nil, activate: (() -> Void)? = nil) {
        self.tab = tab; self.commands = commands; self.activate = activate
        _image = State(initialValue: image)
    }
    @State private var subscription: UUID?
    @State private var pid: Int32?

    static let width: CGFloat = 232
    /// Room for the tallest card, so it never runs past the window's bottom edge.
    static let maxHeight: CGFloat = 240

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: Self.width - 16, height: 112, alignment: .top)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    FaviconView(tab: tab, size: 13).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }
                    Text(tab.displayTitle).font(.system(size: 12, weight: .semibold)).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 4) {
                    Text(tab.addressLabel).lineLimit(1)
                    if let detail { Text("·"); Text(detail).lineLimit(1) }
                }
                .font(.system(size: 10.5)).foregroundStyle(.secondary)
                .padding(.leading, 19)
            }
            .padding(.horizontal, image == nil ? 4 : 2).padding(.vertical, image == nil ? 3 : 0)
            if let activate { Button("Open Tab", action: activate).buttonStyle(.borderedProminent).controlSize(.small) }
        }
        .padding(8).frame(width: Self.width, alignment: .leading)
        .task {
            pid = commands?.performanceTabs().first { $0.id == tab.id }?.pid
            if !tab.isHibernating { subscription = PerformanceMonitor.shared.subscribe() }
        }
        .onDisappear {
            if let subscription { PerformanceMonitor.shared.unsubscribe(subscription) }
            subscription = nil
            image = nil
        }
    }

    private var detail: String? {
        if tab.isHibernating { return "Unloaded" }
        guard let pid, let process = PerformanceMonitor.shared.sample.rows.first(where: { $0.id == pid }) else { return nil }
        return PerformanceSample.bytes(process.memory)
    }
}

extension View {
    func tabPeek(_ tab: TabItem, commands: BrowserCommands?) -> some View {
        background(TabPeekRegion(tabID: tab.id, commands: commands))
    }
}

private struct TabPeekRegion: FillingViewRepresentable {
    let tabID: String
    weak var commands: BrowserCommands?
    func makeNSView(context: Context) -> TabPeekAnchor {
        let view = TabPeekAnchor()
        view.tabID = tabID; view.commands = commands
        return view
    }
    func updateNSView(_ view: TabPeekAnchor, context: Context) {
        // A row reused for another tab: the old tab's card (or pending one) must not outlive it.
        if view.tabID != tabID { view.retire() }
        view.tabID = tabID; view.commands = commands
    }
}

private final class TabPeekAnchor: NSView {
    var tabID = ""
    weak var commands: BrowserCommands?
    private var pending: DispatchWorkItem?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let window = self.window, let content = window.contentView, window.isKeyWindow,
                  (window.firstResponder as? NSTextView)?.isFieldEditor != true,
                  // Still under the pointer: the row may have moved away without an exit event.
                  self.bounds.contains(self.convert(window.mouseLocationOutsideOfEventStream, from: nil)) else { return }
            self.commands?.showTabHover(self.tabID, anchor: self.convert(self.bounds, to: content))
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }
    override func mouseExited(with event: NSEvent) {
        pending?.cancel()
        commands?.hideTabHover(tabID)
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { retire() }
    }
    func retire() { pending?.cancel(); pending = nil; commands?.hideTabHover(tabID) }
    isolated deinit { pending?.cancel() }
}
