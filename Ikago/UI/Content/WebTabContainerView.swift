import AppKit

/// The rounded content surface. Shows 1–4 tab host views side by side in a native
/// NSSplitView; hidden tabs are parked (still alive, still in the window) so switching
/// back is instant and never reloads. Web views autoresize with their panes.
final class WebTabContainerView: NSView {
    /// Pane corner radius; 0 when the border is 0 (edge to edge).
    static var cornerRadius: CGFloat = Radius.card
    /// Top Tabs: the address bar above is the card's top, so only the bottom corners round.
    static var squareTop = false
    private let panes = PaneSplitView()
    private let parking = NSView()
    private(set) var shownIDs: [String] = []
    private var shownLayout: SplitLayout = .columns
    /// The host views currently arranged, and every split view holding them (the outer one first).
    private var paneViews: [NSView] = []
    private var splits: [NSSplitView] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        parking.isHidden = true
        parking.frame = bounds
        parking.autoresizingMask = [.width, .height]
        addSubview(parking)

        panes.dividerStyle = .thin
        panes.frame = bounds
        panes.autoresizingMask = [.width, .height]
        addSubview(panes)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    /// Places exactly `views` (keyed by tab ID) in the pane layout, parking everything else.
    /// Columns and rows are one split view; a grid nests split views (2 × 2, or one tall pane
    /// beside two stacked ones).
    func show(_ views: [(id: String, view: NSView)], layout: SplitLayout, animate: Bool = true) {
        let ids = views.map(\.id)
        let layout = layout.effective(count: views.count)
        // Core Animation stores CATransition under its reserved transition key.
        if !animate { layer?.removeAnimation(forKey: "transition") }
        guard ids != shownIDs || layout != shownLayout else { return }
        if animate, window != nil, !shownIDs.isEmpty {
            // Panes appearing, leaving or rotating cross-fade instead of jumping.
            let fade = CATransition()
            fade.type = .fade
            fade.duration = 0.14
            fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer?.add(fade, forKey: "transition")
        }
        // Dismantle the old arrangement. Views never leave the window on the way (each moves straight to its pane or to
        // parking): a Chromium page taken out of the window is resized to 0×0, and pages like ChatGPT lost their scroll
        // position and blinked when shown again (`CEFTabSwitchChecks`).
        // (`removeArrangedSubview` would take each view out of the window; split views arrange all their subviews, so
        // moving a view elsewhere is enough.)
        let oldSplits = splits
        for old in paneViews where !views.contains(where: { $0.view === old }) { park(old) }
        // Which panes sit along the top edge: every column, the first row, a grid's top pair.
        let top: Set<Int> = switch layout {
        case .columns: Set(views.indices)
        case .rows: [0]
        case .grid: [0, 1]
        }
        for (index, item) in views.enumerated() {
            // Its final size before it joins the split view, which would otherwise lay it out from 0×0: a Chromium page
            // reports that size to the site, and ChatGPT reset its scroll position (`CEFTabSwitchChecks`).
            if views.count == 1 { item.view.frame = panes.bounds }
            item.view.isHidden = false
            (item.view as? TabHostView)?.touchesTop = top.contains(index)
            Self.round(item.view)
        }
        paneViews = views.map(\.view)
        splits = [panes]
        let v = views.map(\.view)
        func nested(_ items: [NSView], vertical: Bool) -> NSSplitView {
            let split = PaneSplitView()
            split.dividerStyle = .thin
            split.isVertical = vertical
            items.forEach { split.addArrangedSubview($0) }
            splits.append(split)
            return split
        }
        switch layout {
        case .columns, .rows:
            panes.isVertical = layout == .columns
            v.forEach { panes.addArrangedSubview($0) }
        case .grid where v.count == 3:
            panes.isVertical = true
            panes.addArrangedSubview(v[0])
            panes.addArrangedSubview(nested([v[1], v[2]], vertical: false))
        case .grid:
            panes.isVertical = false
            panes.addArrangedSubview(nested([v[0], v[1]], vertical: true))
            panes.addArrangedSubview(nested([v[2], v[3]], vertical: true))
        }
        // Nested split views of the old arrangement are empty now (their panes moved); drop them.
        for split in oldSplits where split !== panes && !splits.contains(where: { $0 === split }) { split.removeFromSuperview() }
        shownIDs = ids
        shownLayout = layout
        panes.layoutSubtreeIfNeeded()
        splits.forEach(distributeEvenly)
    }

    /// Each pane is its own rounded card, so split gaps show the themed window background.
    static func round(_ view: NSView) {
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        // AppKit gives a view's backing layer the view's own coordinate space, so the view's `isFlipped` says which
        // edge minY is (panes aren't flipped: minY is the bottom). The layer's `isGeometryFlipped` doesn't: AppKit sets
        // it to match the flipped NSSplitView around the pane, and reading it rounded the top and squared the bottom.
        let bottom: CACornerMask = view.isFlipped
            ? [.layerMinXMaxYCorner, .layerMaxXMaxYCorner] : [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        // Only panes along the top meet the address bar; lower split panes keep all four corners.
        let touchesTop = (view as? TabHostView)?.touchesTop ?? true
        view.layer?.maskedCorners = squareTop && touchesTop ? bottom
            : [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        view.layer?.masksToBounds = true
    }

    /// With several panes on screen, a thin ring marks the focused one.
    func highlight(_ focusedID: String?, views: [(id: String, view: NSView)], color: NSColor) {
        let ring = views.count > 1
        for item in views {
            item.view.layer?.borderWidth = ring && item.id == focusedID ? 2 : 0
            item.view.layer?.borderColor = color.withAlphaComponent(0.7).cgColor
        }
        for view in parking.subviews { view.layer?.borderWidth = 0 }
    }

    func setPaneBackground(_ color: NSColor) {
        for view in paneViews + parking.subviews { view.layer?.backgroundColor = color.cgColor }
    }

    func park(_ view: NSView) {
        guard view.superview !== parking else { return }
        // Straight into parking (addSubview moves it), never out of the window first: a Chromium page out of the
        // window is resized to 0×0 (`CEFTabSwitchChecks`).
        parking.addSubview(view)
        // A split view put it on Auto Layout; with no constraints in parking that sized it to 0×0.
        view.translatesAutoresizingMaskIntoConstraints = true
        view.autoresizingMask = [.width, .height]
        view.frame = parking.bounds
    }

    private func distributeEvenly(_ split: NSSplitView) {
        split.layoutSubtreeIfNeeded()
        let count = split.arrangedSubviews.count
        guard count > 1 else { return }
        let total = (split.isVertical ? split.bounds.width : split.bounds.height) - split.dividerThickness * CGFloat(count - 1)
        for i in 0..<(count - 1) {
            split.setPosition(total / CGFloat(count) * CGFloat(i + 1) + split.dividerThickness * CGFloat(i), ofDividerAt: i)
        }
    }
}

private final class PaneSplitView: NSSplitView {
    override var dividerThickness: CGFloat { 6 }
    override var dividerColor: NSColor { .clear }
    /// Each pane's share of the split, as the person left it. Resizing (the window, the sidebar, a layout switch) keeps
    /// the shares: Auto Layout alone hands the change to one pane, and a layout switch that squeezes the page area for a
    /// moment collapsed a grid's right column to 0 pt and never gave it back (measured with the `panes` test action).
    private var shares: [CGFloat] = []
    private var lastRoom: CGFloat = 0

    override func layout() {
        super.layout()
        let panes = arrangedSubviews
        let room = (isVertical ? bounds.width : bounds.height) - dividerThickness * CGFloat(max(0, panes.count - 1))
        guard panes.count > 1, room > CGFloat(panes.count) * 40 else { return }
        let lengths = panes.map { isVertical ? $0.frame.width : $0.frame.height }
        let collapsed = lengths.contains { $0 < 1 }
        let known = shares.count == panes.count
        // A split laid out collapsed before it ever had room (a new grid in a window not yet on screen) shares evenly.
        if (room != lastRoom && known) || collapsed {
            let wanted = known ? shares : Array(repeating: 1 / CGFloat(panes.count), count: panes.count)
            lastRoom = room
            var edge: CGFloat = 0
            for i in 0..<(panes.count - 1) {
                edge += (room * wanted[i]).rounded()
                setPosition(edge + dividerThickness * CGFloat(i), ofDividerAt: i)
            }
        } else if !collapsed {
            // The same room: a divider moved (or new panes were laid out), so these are the shares to keep.
            lastRoom = room
            let sum = lengths.reduce(0, +)
            shares = lengths.map { $0 / sum }
        }
    }
}
