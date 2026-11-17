import SwiftUI

/// Three groups in a row: the first at the start, the last at the end, the middle one centred. When the middle one
/// would run into a side group it slides along the row to keep `gap` clear of both (centred between them when even that
/// doesn't fit), so the groups never overlap.
struct ThreeSlotLayout: Layout {
    var gap: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let natural = sizes.reduce(0) { $0 + $1.width } + gap * CGFloat(max(0, sizes.count - 1))
        return CGSize(width: proposal.width ?? natural, height: sizes.map(\.height).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else {
            var x = bounds.minX
            for view in subviews {
                let size = view.sizeThatFits(.unspecified)
                view.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(size))
                x += size.width + gap
            }
            return
        }
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(sizes[0]))
        subviews[2].place(at: CGPoint(x: bounds.maxX, y: bounds.midY), anchor: .trailing, proposal: ProposedViewSize(sizes[2]))
        let low = bounds.minX + (sizes[0].width > 0 ? sizes[0].width + gap : 0)
        let high = bounds.maxX - (sizes[2].width > 0 ? sizes[2].width + gap : 0) - sizes[1].width
        var x = bounds.midX - sizes[1].width / 2
        x = high >= low ? min(max(x, low), high) : (low + high) / 2
        subviews[1].place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(sizes[1]))
    }
}
