import AppKit
import SwiftUI

/// The rows' host: sized by the scroll view, with no Auto Layout and no size reporting of its own.
final class ListHostingView<Content: View>: NSHostingView<Content> {
    required init(rootView: Content) {
        super.init(rootView: rootView)
        sizingOptions = []
        safeAreaRegions = []
        translatesAutoresizingMaskIntoConstraints = true
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    private var laidOutSize = NSSize.zero

    override func layout() {
        // See `ListScrollView.pausesRowUpdates`. A resize always lays out.
        if frame.size == laidOutSize, (enclosingScrollView as? ListScrollView)?.pausesRowUpdates == true { return }
        laidOutSize = frame.size
        super.layout()
    }
}

extension EnvironmentValues {
    /// True while the enclosing sidebar list scrolls; rows ignore hover then.
    @Entry var sidebarScrolling = false
}

extension View {
    /// `onHover` for sidebar rows: ignored while the list scrolls, and cleared when scrolling starts.
    func sidebarHover(_ hovering: Binding<Bool>) -> some View { modifier(SidebarHover(hovering: hovering)) }
}

private struct SidebarHover: ViewModifier {
    @Binding var hovering: Bool
    @Environment(\.sidebarScrolling) private var scrolling

    func body(content: Content) -> some View {
        content
            .onHover { inside in if !scrolling, hovering != inside { hovering = inside } }
            .onChange(of: scrolling) { _, now in if now, hovering { hovering = false } }
    }
}
