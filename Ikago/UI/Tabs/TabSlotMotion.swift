import SwiftUI

/// Tab row motion (Sidebar + Tabs): an opened tab grows out of its slot while its neighbours and the + button slide aside, a closed
/// tab shrinks to nothing while they slide in, and widths reflow smoothly when tabs open, close,
/// or reorder. Window resizes and Space switches stay immediate.
enum TabMotion {
    static let duration: Double = 0.2

    static func animation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: duration)
    }
}

/// What a strip animates on: its items (opening, closing, reordering, groups collapsing).
/// Selection stays immediate, and widths that change for any other reason (a window
/// resize, switching tabs in a crowded strip) don't animate.
struct TabMotionKey: Equatable {
    let ids: [String]
    /// Tabs keeping their width after a close under the pointer; letting go reflows them on the same motion.
    var held = false
}

extension View {
    /// The strip row's motion: no transaction a caller opens reaches it, its own changes animate,
    /// and switching Spaces swaps the strip without motion.
    func tabStripMotion(_ key: TabMotionKey, space: UUID, reduceMotion: Bool) -> some View {
        animation(nil, value: space)
            .animation(TabMotion.animation(reduceMotion: reduceMotion), value: key)
            .transaction { $0.animation = nil }
    }

    /// The slot transition for one strip item.
    func tabSlot() -> some View {
        transition(.modifier(active: TabSlotReveal(fraction: 0), identity: TabSlotReveal(fraction: 1)))
    }
}

/// Reports `fraction` of the item's own width and clips horizontally,
/// so the strip's layout, and everything after the item, follows the growing or shrinking slot.
struct TabSlotReveal: ViewModifier, Animatable {
    var fraction: CGFloat
    nonisolated var animatableData: CGFloat {
        get { fraction }
        set { fraction = newValue }
    }

    func body(content: Content) -> some View {
        SlotLayout(fraction: fraction) { content }
            .clipShape(HorizontalClip(open: fraction >= 1))
            // A slot on its way in or out fades with its width and draws under its neighbours, so a closing tab never
            // covers the tab before it (whose selected shape now reaches into its space).
            .opacity(fraction >= 1 ? 1 : Double(min(1, max(0, fraction) * 1.4)))
            .zIndex(fraction >= 1 ? 0 : -1)
    }
}

private struct SlotLayout: Layout {
    let fraction: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first?.sizeThatFits(proposal) else { return .zero }
        let width = fraction >= 1 ? child.width : child.width * max(0, fraction)
        return CGSize(width: max(0, width), height: child.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let child = subviews.first else { return }
        let size = child.sizeThatFits(proposal)
        child.place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(size))
    }
}

/// Clips only the sides while the slot grows or shrinks, so shadows and fills above and below are kept. A settled slot
/// isn't clipped at all: an attached tab's flares reach past its frame into the page.
private struct HorizontalClip: Shape {
    var open = false
    func path(in rect: CGRect) -> Path { Path(rect.insetBy(dx: open ? -40 : 0, dy: -40)) }
}
