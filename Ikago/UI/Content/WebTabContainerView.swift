import AppKit

/// The rounded content surface. Shows 1–4 tab host views side by side in a native
/// NSSplitView; hidden tabs are parked (still alive, still in the window) so switching
/// back is instant and never reloads. Web views autoresize with their panes.
final class WebTabContainerView: NSView {
    /// Pane corner radius; 0 when the border is 0 (edge to edge).
    static var cornerRadius: CGFloat = 12
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
        // Dismantle the old arrangement; the live views go to parking until they are placed.
        for split in splits {
            for view in split.arrangedSubviews { split.removeArrangedSubview(view); view.removeFromSuperview() }
        }
        for item in views {
            item.view.removeFromSuperview()
            item.view.isHidden = false
            Self.round(item.view)
        }
        // Anything still shown from before that is no longer wanted is parked.
        for old in paneViews where !views.contains(where: { $0.view === old }) { park(old) }

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
        view.removeFromSuperview()
        view.frame = parking.bounds
        parking.addSubview(view)
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
}
