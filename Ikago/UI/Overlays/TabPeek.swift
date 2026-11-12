import SwiftUI

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
        }
        .onDisappear {
            if let subscription { PerformanceMonitor.shared.unsubscribe(subscription) }
            subscription = nil
            image = nil
        }
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
    func updateNSView(_ view: TabPeekAnchor, context: Context) { view.tabID = tabID; view.commands = commands }
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
            guard let self, let window = self.window, let content = window.contentView,
                  (window.firstResponder as? NSTextView)?.isFieldEditor != true else { return }
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
        if window == nil { pending?.cancel(); commands?.hideTabHover(tabID) }
    }
    isolated deinit { pending?.cancel() }
}
