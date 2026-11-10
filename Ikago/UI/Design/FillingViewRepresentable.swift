import SwiftUI

/// An AppKit view that takes exactly the space SwiftUI offers it (a background, an overlay, a host, a scroll view).
///
/// Without this, SwiftUI asks AppKit for the view's `fittingSize` on every layout, which builds a temporary Auto Layout
/// engine each time. Measured while switching tabs, that was the largest single cost on the main thread: more than
/// SwiftUI's own rendering. Every tab row carries such a view (`onMiddleClick`), and the page's host holds a web view.
protocol FillingViewRepresentable: NSViewRepresentable {}

extension FillingViewRepresentable {
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSViewType, context: Context) -> CGSize? {
        // An open-ended proposal keeps SwiftUI's default answer.
        guard let width = proposal.width, let height = proposal.height, width.isFinite, height.isFinite else { return nil }
        return CGSize(width: width, height: height)
    }
}
