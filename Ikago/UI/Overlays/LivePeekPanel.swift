import SwiftUI

struct LivePeekPanel: View {
    let page: NSView
    weak var commands: BrowserCommands?
    let colors: Palette
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { commands?.closePeek() } label: { Image(systemName: "xmark") }
                Spacer()
                Text("Peek").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                Button("Open Tab") { commands?.openPeek() }
            }.buttonStyle(.plain).padding(14)
            PeekContent(view: page)
        }.surface(RoundedRectangle(cornerRadius: 18), colors)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .task { await Task.yield(); commands?.focusPeek() }
            .onExitCommand { commands?.closePeek() }
    }
}
private struct PeekContent: FillingViewRepresentable {
    let view: NSView
    func makeNSView(context: Context) -> NSView { let wrapper = NSView(); attach(wrapper); return wrapper }
    func updateNSView(_ wrapper: NSView, context: Context) { attach(wrapper) }
    private func attach(_ wrapper: NSView) {
        if view.superview !== wrapper { view.removeFromSuperview(); wrapper.addSubview(view) }
        view.isHidden = false
        view.frame = wrapper.bounds; view.autoresizingMask = [.width, .height]
    }
}
