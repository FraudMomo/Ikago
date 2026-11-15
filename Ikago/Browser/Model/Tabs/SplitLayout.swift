import CoreGraphics

/// How a split group's panes are arranged.
enum SplitLayout: String, Codable, CaseIterable {
    /// Side by side.
    case columns
    /// Stacked.
    case rows
    /// 3 panes: one tall pane and two stacked beside it; 4 panes: 2 × 2.
    case grid

    /// What "Rotate Split" switches to (a grid only makes sense from 3 panes).
    func next(count: Int) -> SplitLayout {
        switch self {
        case .columns: .rows
        case .rows: count >= 3 ? .grid : .columns
        case .grid: .columns
        }
    }

    /// The layout actually drawn for `count` panes.
    func effective(count: Int) -> SplitLayout { self == .grid && count < 3 ? .columns : self }

    /// Pane rectangles (top-left origin) for `count` panes in `size`, separated by `gap`.
    func rects(count: Int, in size: CGSize, gap: CGFloat = 6) -> [CGRect] {
        let w = size.width, h = size.height
        func slice(_ i: Int, of n: Int, length: CGFloat) -> (CGFloat, CGFloat) {
            let each = (length - gap * CGFloat(n - 1)) / CGFloat(n)
            return (CGFloat(i) * (each + gap), each)
        }
        switch effective(count: count) {
        case .columns:
            return (0..<count).map { i in let s = slice(i, of: count, length: w); return CGRect(x: s.0, y: 0, width: s.1, height: h) }
        case .rows:
            return (0..<count).map { i in let s = slice(i, of: count, length: h); return CGRect(x: 0, y: s.0, width: w, height: s.1) }
        case .grid:
            let colW = (w - gap) / 2, rowH = (h - gap) / 2
            if count == 3 {
                return [CGRect(x: 0, y: 0, width: colW, height: h),
                        CGRect(x: colW + gap, y: 0, width: colW, height: rowH),
                        CGRect(x: colW + gap, y: rowH + gap, width: colW, height: rowH)]
            }
            return (0..<count).map { i in
                CGRect(x: CGFloat(i % 2) * (colW + gap), y: CGFloat(i / 2) * (rowH + gap), width: colW, height: rowH)
            }
        }
    }
}

/// Which edge of the page a tab is dropped on to join split view.
enum SplitEdge { case left, right, top, bottom
    var isLeading: Bool { self == .left || self == .top }
    var isHorizontalAxis: Bool { self == .left || self == .right }
}
