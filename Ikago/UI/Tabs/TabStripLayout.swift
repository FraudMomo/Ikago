import SwiftUI

/// Top-tab sizing with a two-step shrink.
/// Every regular tab shares one width down to `minimumActive`, so titles stay readable as long as
/// possible. Past that the active tab keeps `minimumActive` while inactive tabs compact toward
/// `minimumInactive` (a favicon), and only once every tab is at its minimum does the strip scroll.
/// Passing equal minimums keeps every tab readable and scrolls instead of compacting.
@MainActor
struct TabStripLayout {
    static let spacing: CGFloat = 3
    static let groupInset: CGFloat = 2
    static let pinned: CGFloat = 28
    static let maxTab: CGFloat = 150
    static let minTab: CGFloat = 120
    static let chipMax: CGFloat = 120
    /// Below this width an inactive tab shows only its favicon (and its close button on hover).
    static let iconOnlyWidth: CGFloat = 72

    /// Width of an inactive regular tab (the active tab may be wider while compacted).
    let tab: CGFloat
    /// Whether inactive tabs are narrower than the active tab.
    let compact: Bool
    let natural: CGFloat
    /// Width of each split-group chip.
    let chip: CGFloat
    private let widths: [String: CGFloat]
    private let pinnedWidth: CGFloat

    init(items: [TabListItem], available: CGFloat, expandedGroups: Int = 0,
         groupStyle: GroupLabelStyle = .minimal, showGroupCounts: Bool = true,
         maximumTab: CGFloat = Self.maxTab, pinnedWidth: CGFloat = Self.pinned, spacing: CGFloat = Self.spacing,
         activeID: String? = nil, minimumActive: CGFloat = Self.minTab, minimumInactive: CGFloat? = nil) {
        self.pinnedWidth = pinnedWidth
        // A lone tab in a tiny viewport still fits.
        let fit = max(32, available - 6)
        let crossover = min(minimumActive, fit)
        let floor = min(minimumInactive ?? minimumActive, crossover)
        var fixed: CGFloat = 6 + CGFloat(max(0, items.count - 1)) * spacing
            + CGFloat(expandedGroups) * Self.groupInset * 2
        var slots: [(id: String, active: Bool, chip: Bool)] = []
        for item in items {
            switch item {
            case .tab(let tab):
                if tab.pinned { fixed += pinnedWidth } else { slots.append((tab.id, tab.id == activeID, false)) }
            case .folder(let folder, let count):
                fixed += FolderChip.width(of: folder, count: count, style: groupStyle, showsCount: showGroupCounts)
                    + (spacing < 0 ? 2 * (Self.spacing - spacing) : 0)
            case .group(let tabs):
                fixed += 6 + CGFloat(max(0, tabs.count - 1)) * 2
                slots += tabs.map { ($0.id, false, true) }
            }
        }
        let space = available - fixed
        // The Separate row fills the space (an unbounded maximum): no tab is wider than the row.
        func preferred(_ chip: Bool) -> CGFloat { max(crossover, min(chip ? Self.chipMax : maximumTab, max(crossover, space))) }
        func minimum(_ active: Bool) -> CGFloat { active ? crossover : floor }
        let crossSum = CGFloat(slots.count) * crossover
        let minSum = slots.reduce(0) { $0 + minimum($1.active) }
        let prefSum = slots.reduce(0) { $0 + preferred($1.chip) }
        let below = space < crossSum
        let low = below ? minSum : crossSum, high = below ? crossSum : prefSum
        let fraction = high == low ? 1 : min(1, max(0, (space - low) / (high - low)))
        var widths: [String: CGFloat] = [:]
        var total: CGFloat = 0
        for slot in slots {
            let from = below ? minimum(slot.active) : crossover, to = below ? crossover : preferred(slot.chip)
            let width = (from + fraction * (to - from)).rounded(.down)
            widths[slot.id] = width
            total += width
        }
        self.widths = widths
        let inactive = below ? (floor + fraction * (crossover - floor)).rounded(.down)
                             : (crossover + fraction * (preferred(false) - crossover)).rounded(.down)
        tab = slots.isEmpty ? min(maximumTab, max(crossover, space)) : inactive
        chip = slots.first(where: \.chip).flatMap { widths[$0.id] } ?? min(tab, Self.chipMax)
        compact = below && floor < crossover && fraction < 1
        natural = fixed + total
    }

    func width(of tab: TabItem) -> CGFloat {
        tab.pinned ? pinnedWidth : widths[tab.id] ?? self.tab
    }
}
