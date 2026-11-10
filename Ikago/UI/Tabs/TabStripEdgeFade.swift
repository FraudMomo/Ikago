import SwiftUI

/// Only fade an edge when more content lies beyond it. The first/last tab keeps full contrast.
struct TabScrollEdges: Equatable {
    var leading = false
    var trailing = false

    init() {}
    init(_ geometry: ScrollGeometry) {
        leading = geometry.visibleRect.minX > 1
        trailing = geometry.visibleRect.maxX < geometry.contentSize.width - 1
    }
}

struct TabStripEdgeFade: View {
    let edges: TabScrollEdges

    var body: some View {
        GeometryReader { geometry in
            let fade = min(0.25, 18 / max(1, geometry.size.width))
            LinearGradient(stops: [
                .init(color: edges.leading ? .clear : .black, location: 0),
                .init(color: .black, location: fade),
                .init(color: .black, location: 1 - fade),
                .init(color: edges.trailing ? .clear : .black, location: 1)
            ], startPoint: .leading, endPoint: .trailing)
        }
    }
}
