import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The sidebar's list on AppKit's own outline view (`NSOutlineView`, as in Finder's and Mail's sidebars), with the
/// outline's own drag and drop: the rows part where a dragged row will land.
///
/// This file only shows rows and asks the model. What the rows are and where a drop lands is `SidebarOutline`; here a
/// drop's pointer is turned into a target (`target(_:)`), the model says the place, and the gap is set to show it. Rows
/// that stay keep their views. The outline holds exactly the rows on screen: an open group's rows, never a shut one's,
/// so what it holds is always what the model shows (`update`).
///
/// Clicks on a row's body reach the outline (select, open a group, drag); the row's own controls (close, mute, camera),
/// right clicks (its menu) and middle clicks reach the row.
struct SidebarOutlineList: View {
    let state: BrowserState
    let chrome: ChromeModel
    let colors: Palette
    weak var commands: BrowserCommands?
    var onSelection: (() -> Void)? = nil
    /// The icon sidebar's tiles in place of the rows (`SidebarRail`).
    var rail: OutlineRailCells? = nil
    @Environment(\.self) private var environment

    var body: some View {
        // Reading the structure here is what makes the list follow it; each row observes its own tab or group. The
        // essentials row's height too: the list must be told when it changes.
        let outline = Self.shown(state, rail: rail)
        let essentials = rail == nil ? SidebarEssentials.height(state) : 0
        let style = OutlineStyle(cards: rail != nil || state.groupsAsPills, pills: rail == nil && state.groupsAsPills,
                                 isDark: colors.isDark,
                                 // The rows live in other hosts: a change of mode reaches them only when they're given it.
                                 scheme: environment.colorScheme)
        OutlineRepresentable(outline: outline, style: style, state: state, chrome: chrome, colors: colors,
                             commands: commands, onSelection: onSelection, environment: environment, rail: rail,
                             essentialsHeight: essentials)
            .recordLayout(rail == nil ? "sidebar-tab-list" : "rail-tab-list")
    }

    /// The rows this list shows: the model's, without the divider when New Tab is off, without the loose tabs under Top
    /// Tabs (the tab row has them), and through the icon sidebar's filter (which shows the essentials as its own tiles).
    @MainActor static func shown(_ state: BrowserState, rail: OutlineRailCells?) -> SidebarOutline {
        var full = state.sidebarOutline.rows
        if rail != nil { full.removeAll { $0.kind == .essentials } }
        let topTabs = state.showsSidebarTopTabs
        let divider = state.chromeLayout.sidebarShowsNewTab && !topTabs
        var loose = false
        var rows: [SidebarOutline.Row] = []
        for row in full {
            if row.kind == .divider {
                loose = true
                if divider { rows.append(row) }
            } else if !(loose && topTabs && row.groupID == nil) {
                rows.append(row)
            }
        }
        let outline = SidebarOutline(rows: rows)
        return rail.map { $0.filter(outline) } ?? outline
    }
}

/// How the icon sidebar draws the list: its own tile per row, in one 36 pt column, with the group's tint behind that
/// column only. Moving rows is the full sidebar's.
struct OutlineRailCells {
    /// A row's tile: a tab (a split row's tiles stacked), a group, the New Tab tile.
    let cell: @MainActor (SidebarOutline.Row) -> AnyView
    let height: @MainActor (SidebarOutline.Row) -> CGFloat
    /// The rows the rail leaves out (pins shown as Essentials or in the tab row, groups kept in the tab row).
    let filter: @MainActor (SidebarOutline) -> SidebarOutline
    /// The rail's list for the hover effects (`RailSurface.list`): it is pointed at the list, and told when it scrolls.
    let space: RailSpace
    let onScroll: @MainActor () -> Void
    /// Where the tile column starts.
    let inset: CGFloat
}

/// What changes how every row is drawn.
struct OutlineStyle: Equatable {
    var cards: Bool
    var pills: Bool
    var isDark: Bool
    var scheme: ColorScheme
}

private struct OutlineRepresentable: FillingViewRepresentable {
    let outline: SidebarOutline
    let style: OutlineStyle
    let state: BrowserState
    let chrome: ChromeModel
    let colors: Palette
    weak var commands: BrowserCommands?
    let onSelection: (() -> Void)?
    let environment: EnvironmentValues
    let rail: OutlineRailCells?
    let essentialsHeight: CGFloat

    func makeCoordinator() -> SidebarOutlineController {
        SidebarOutlineController(state: state, chrome: chrome, rail: rail)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let controller = context.coordinator
        let scrollView = OutlineScrollView()
        scrollView.contentView = OutlineClipView()
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = false
        // The full sidebar's list spans the sidebar's 10 pt margins and its rows sit in from them (`insets(for:)`), so the
        // scroller runs in the trailing margin, clear of the rows. (Not content insets: AppKit placed the floating
        // essentials row by them, partway, while a drag moved the gap, and the grid jumped sideways.)
        scrollView.contentInsets = NSEdgeInsetsZero
        scrollView.scrollerInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: rail == nil ? 1 : 0)
        scrollView.verticalScroller = SlimScroller()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.hasHorizontalScroller = false
        scrollView.horizontalScrollElasticity = .none
        scrollView.documentView = controller.outlineView
        if rail == nil {
            scrollView.takesDrops(like: controller.outlineView)
            scrollView.essentialsRect = { [weak controller] in controller?.essentialsRect }
        }
        controller.attachRail(to: scrollView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let controller = context.coordinator
        controller.colors = colors
        controller.commands = commands
        controller.onSelection = onSelection
        // The icon sidebar's tiles take part in Magnify through their environment: each row's view holds the one it was
        // made with, so when the effect comes or goes the rows are made again, or tiles made before stayed out of it.
        if controller.environment.railHover !== environment.railHover { controller.needsRebuild = true }
        controller.environment = environment
        controller.essentialsHeight = essentialsHeight
        if let rail { controller.rail = rail }
        controller.show(outline, style: style)
    }
}

// MARK: - Controller

/// One row of the outline as the view knows it: a stable object per row id, as `NSOutlineView` needs.
final class OutlineNode: NSObject {
    let id: String
    var row: SidebarOutline.Row
    /// The rows the outline holds under it: an open group's rows, none for a shut group or a tab.
    var children: [OutlineNode] = []
    weak var parent: OutlineNode?
    var depth = 0
    /// The height the outline last asked for: when a row's height changes, the outline has to be told, or its cached
    /// heights go stale and opening a drop gap crashes inside AppKit.
    var shownHeight: CGFloat?
    init(_ row: SidebarOutline.Row) {
        id = row.id
        self.row = row
    }
}

@MainActor
final class SidebarOutlineController: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
    let state: BrowserState
    let chrome: ChromeModel
    var colors: Palette
    weak var commands: BrowserCommands?
    var onSelection: (() -> Void)?
    var environment = EnvironmentValues()
    /// The rows' views must be made again (their environment changed), at the next `show`.
    var needsRebuild = false
    let outlineView = SidebarOutlineTable()
    /// What the list shows now.
    private(set) var outline = SidebarOutline(rows: [])
    private var roots: [OutlineNode] = []
    private var nodes: [String: OutlineNode] = [:]
    private var style = OutlineStyle(cards: true, pills: true, isDark: false, scheme: .light)

    /// The icon sidebar's tiles in place of the rows.
    var rail: OutlineRailCells?
    /// Each tile's own space for the hover effects (a tile measures itself in its cell, which converts to the window).
    private var railSpaces: [String: RailSpace] = [:]
    private var scrollObserver: NSObjectProtocol?

    /// The essentials row's height (`SidebarEssentials.height`), given with each update.
    var essentialsHeight: CGFloat = 0

    init(state: BrowserState, chrome: ChromeModel, rail: OutlineRailCells? = nil) {
        self.state = state
        self.chrome = chrome
        self.rail = rail
        colors = state.palette
        super.init()
        #if DEBUG
        Self.made.add(self)
        #endif
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("row"))
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.style = .plain
        outlineView.backgroundColor = .clear
        outlineView.intercellSpacing = NSSize(width: 0, height: rail == nil ? 2 : 4)
        // The gap a drag opens is this tall: a tab row's (the rows set their own heights).
        outlineView.rowHeight = rail == nil ? 34 : 36
        outlineView.indentationPerLevel = 0
        outlineView.indentationMarkerFollowsCell = false
        outlineView.autoresizesOutlineColumn = false
        outlineView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        outlineView.selectionHighlightStyle = .none
        outlineView.allowsEmptySelection = true
        // The full sidebar's essentials stay at the top while the rest scrolls, as the icon sidebar's do: their row is
        // AppKit's floating group row (`isGroupItem`), and rows passing under it are hidden (`maskUnderEssentials`).
        outlineView.floatsGroupRows = rail == nil
        outlineView.focusRingType = .none
        outlineView.draggingDestinationFeedbackStyle = .gap
        outlineView.setDraggingSourceOperationMask([.move, .generic], forLocal: true)
        outlineView.setDraggingSourceOperationMask([.move, .generic, .copy], forLocal: false)
        outlineView.registerForDraggedTypes([NSPasteboard.PasteboardType(UTType.ikagoTab.identifier),
                                             NSPasteboard.PasteboardType(UTType.ikagoGroup.identifier)])
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.onClick = { [weak self] row in self?.clicked(row) }
        outlineView.onDragMoved = { [weak self] info in self?.updateDrop(info) ?? [] }
        outlineView.onDrop = { [weak self] info in self?.takeDrop(info) ?? false }
        outlineView.onDragFinished = { [weak self] in self?.dropFinished() }
    }

    /// The icon sidebar: its list space is this list, and its scrolling is reported (the hover effects' copy follows).
    func attachRail(to scrollView: NSScrollView) {
        guard let rail else {
            let clip = scrollView.contentView
            clip.postsBoundsChangedNotifications = true
            scrollObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.maskUnderEssentials() }
            }
            return
        }
        rail.space.view = outlineView
        let clip = scrollView.contentView
        clip.postsBoundsChangedNotifications = true
        scrollObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.rail?.onScroll() }
        }
    }

    // MARK: Following the model

    /// Shows `new`, animated unless `animated` is false (a drop: its rows go where the gap was) or Reduce Motion is on.
    /// While a drag from this list is under way the rows stay as AppKit knows them (`isDragSource`), and the list
    /// catches up when the drag ends (`dropFinished`): a drop elsewhere (the essentials grid, the list above it) changed
    /// them mid-drag, and AppKit's end of the drag crashed in `setGapRow:`.
    func show(_ new: SidebarOutline, style: OutlineStyle, animated: Bool = true) {
        guard !outlineView.isDragSource else {
            heldWhileDragging = true
            return
        }
        let restyle = style != self.style || needsRebuild
        needsRebuild = false
        self.style = style
        // The rows' system colors (`.secondary` symbols) follow the sidebar's mode, which can differ from the window's.
        outlineView.appearance = NSAppearance(named: style.scheme == .dark ? .darkAqua : .aqua)
        if new != outline {
            outline = new
            update(to: new, animated: animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        }
        noteChangedHeights()
        maskUnderEssentials()
        place(rebuilding: restyle)
    }

    /// Takes the outline from the rows it holds to `new`'s, in place. The data source says the new rows first (as
    /// AppKit expects), then the outline is told: in each list it holds, from the top (so a row's new group is there
    /// before it arrives), rows are put in order, each moved from wherever it is or inserted; what is left at the end
    /// of a list afterwards is no longer there and goes. A shut group holds no rows, so a group opens by taking its
    /// rows (AppKit reads them as it expands it) and shuts by losing them.
    private func update(to new: SidebarOutline, animated: Bool) {
        // What the outline holds now, list by list (nil: the top level): the top and every open group's rows.
        var held: [ObjectIdentifier?: [OutlineNode]] = [:]
        var heldParent: [ObjectIdentifier: OutlineNode?] = [:]
        func record(_ list: [OutlineNode], under parent: OutlineNode?) {
            held[parent.map(ObjectIdentifier.init)] = list
            for node in list {
                heldParent[ObjectIdentifier(node)] = parent
                if node.row.groupID != nil, outlineView.isItemExpanded(node) { record(node.children, under: node) }
            }
        }
        record(roots, under: nil)

        // The new rows as nodes (a row keeps its node, so its view), and the lists to tell, top-down.
        var fresh: [String: OutlineNode] = [:]
        var lists: [(parent: OutlineNode?, nodes: [OutlineNode])] = []
        func build(_ rows: [SidebarOutline.Row], parent: OutlineNode?, depth: Int) -> [OutlineNode] {
            let list = rows.map { row in
                let node = nodes[row.id] ?? OutlineNode(row)
                fresh[row.id] = node
                node.row = row
                node.parent = parent
                node.depth = depth
                return node
            }
            lists.append((parent, list))
            for node in list where node.row.groupID != nil {
                node.children = build(node.row.isOpen ? node.row.children : [], parent: node, depth: depth + 1)
            }
            return list
        }
        roots = build(new.rows, parent: nil, depth: 0)
        nodes = fresh

        let insert: NSTableView.AnimationOptions = animated ? .slideDown : []
        let remove: NSTableView.AnimationOptions = animated ? .slideUp : []
        NSAnimationContext.runAnimationGroup { context in
            if !animated {
                context.duration = 0
                context.allowsImplicitAnimation = false
            }
            outlineView.beginUpdates()
            // A list the outline doesn't hold (a shut or new group's) it reads when the group opens.
            let told = lists.filter { held[$0.parent.map(ObjectIdentifier.init)] != nil }
            for (parent, list) in told {
                let key = parent.map(ObjectIdentifier.init)
                for (index, node) in list.enumerated() {
                    if held[key]?.indices.contains(index) == true, held[key]?[index] === node { continue }
                    let id = ObjectIdentifier(node)
                    if let source = heldParent[id], let from = held[source.map(ObjectIdentifier.init)]?.firstIndex(where: { $0 === node }) {
                        outlineView.moveItem(at: from, inParent: source, to: index, inParent: parent)
                        held[source.map(ObjectIdentifier.init)]?.remove(at: from)
                    } else {
                        outlineView.insertItems(at: [index], inParent: parent, withAnimation: insert)
                    }
                    held[key, default: []].insert(node, at: index)
                    heldParent[id] = parent
                }
            }
            // Rows still held after a list's new rows are no longer there; they go with whatever they hold. (A list
            // whose group has gone goes with the group.)
            for (parent, list) in told {
                guard let count = held[parent.map(ObjectIdentifier.init)]?.count, count > list.count else { continue }
                outlineView.removeItems(at: IndexSet(list.count..<count), inParent: parent, withAnimation: remove)
            }
            outlineView.endUpdates()
            // A drop's rows take their places now, inside this group, not when AppKit next lays the list out.
            if !animated { outlineView.layoutSubtreeIfNeeded() }
        }
        // Groups open and shut with the model once their rows are in place, from the top (an open group's rows exist).
        func sync(_ list: [OutlineNode]) {
            for node in list where node.row.groupID != nil {
                if node.row.isOpen != outlineView.isItemExpanded(node) {
                    let view = animated ? outlineView.animator() : outlineView
                    if node.row.isOpen { view.expandItem(node) } else { view.collapseItem(node) }
                }
                sync(node.children)
            }
        }
        sync(roots)
    }

    /// Tells the outline about rows whose height changed (a group nested or not, a split row's tiles).
    private func noteChangedHeights() {
        var changed = IndexSet()
        for row in 0..<outlineView.numberOfRows {
            guard let node = outlineView.item(atRow: row) as? OutlineNode, let shown = node.shownHeight else { continue }
            if height(of: node) != shown { changed.insert(row) }
        }
        guard !changed.isEmpty else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            outlineView.noteHeightOfRows(withIndexesChanged: changed)
        }
    }

    /// Every row on screen drawn for its place now: its piece of its group's card and its indent; its content too when
    /// the style changed.
    private func place(rebuilding: Bool) {
        outlineView.enumerateAvailableRowViews { rowView, row in
            guard let node = outlineView.item(atRow: row) as? OutlineNode else { return }
            configure(rowView as? OutlineRowView, node)
            guard let cell = outlineView.view(atColumn: 0, row: row, makeIfNecessary: false) as? OutlineHostingCell else { return }
            if rebuilding { cell.root = content(for: node) }
            cell.insets = insets(for: node)
        }
    }

    // MARK: Data source

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        children(of: item as? OutlineNode).count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        children(of: item as? OutlineNode)[index]
    }

    private func children(of parent: OutlineNode?) -> [OutlineNode] { parent?.children ?? roots }

    /// The essentials' row where it shows now (outline coordinates): floating at the top, or in its place.
    var essentialsRect: NSRect? {
        if let floating = floatingEssentials { return floating.rect }
        guard rail == nil, let node = nodes["essentials"] else { return nil }
        let row = outlineView.row(forItem: node)
        return row >= 0 ? outlineView.rect(ofRow: row) : nil
    }

    /// The essentials' row while it floats at the top of the scrolled list: its index, and where it shows (outline
    /// coordinates). Nil while it sits in its place.
    var floatingEssentials: (row: Int, rect: NSRect)? {
        guard rail == nil, let node = nodes["essentials"] else { return nil }
        let row = outlineView.row(forItem: node)
        let visible = outlineView.visibleRect
        guard row >= 0, outlineView.rect(ofRow: row).minY < visible.minY - 0.5 else { return nil }
        return (row, NSRect(x: visible.minX, y: visible.minY, width: outlineView.bounds.width, height: essentialsHeight))
    }

    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        rail == nil && (item as? OutlineNode)?.row.kind == .essentials
    }

    /// While the essentials float at the top of the scrolled list, the rows scrolling under them are hidden: the sidebar
    /// behind can be see-through, so the floating row has no background of its own to cover them with.
    func maskUnderEssentials() {
        guard rail == nil else { return }
        outlineView.wantsLayer = true
        guard let floating = floatingEssentials else {
            outlineView.layer?.mask = nil
            return
        }
        let mask = outlineView.layer?.mask ?? CALayer()
        mask.backgroundColor = NSColor.black.cgColor
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // The outline is flipped (so is its layer): everything from just under the floating essentials down shows.
        let bounds = outlineView.bounds
        let top = floating.rect.maxY
        mask.frame = CGRect(x: 0, y: top, width: bounds.width, height: max(0, bounds.height - top))
        outlineView.layer?.mask = mask
        CATransaction.commit()
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? OutlineNode)?.row.groupID != nil
    }

    // MARK: Delegate: rows

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        guard let node = item as? OutlineNode else { return 34 }
        let height = height(of: node)
        node.shownHeight = height
        return height
    }

    private func height(of node: OutlineNode) -> CGFloat {
        if let rail { return rail.height(node.row) }
        switch node.row.kind {
        case .tabs: return 34
        case .divider: return 45
        case .essentials: return essentialsHeight
        case .group: return node.depth > 0 ? 30 : style.pills ? 32 : 34
        }
    }

    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        let rowView = OutlineRowView()
        if let node = item as? OutlineNode { configure(rowView, node) }
        return rowView
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? OutlineNode else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("cell")
        let cell = outlineView.makeView(withIdentifier: identifier, owner: nil) as? OutlineHostingCell ?? OutlineHostingCell(identifier: identifier)
        cell.kind = node.row.kind
        cell.railInset = rail?.inset
        cell.root = content(for: node)
        cell.insets = insets(for: node)
        return cell
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool { false }

    func outlineViewItemDidExpand(_ notification: Notification) { place(rebuilding: false) }
    func outlineViewItemDidCollapse(_ notification: Notification) { place(rebuilding: false) }

    /// A row's place in its group's card (Cards style): the card is the top-level group's header and every row under it
    /// while it is open, drawn piece by piece by the rows.
    private func configure(_ rowView: OutlineRowView?, _ node: OutlineNode) {
        guard let rowView else { return }
        var top = node
        while let parent = top.parent { top = parent }
        guard style.cards, let groupID = top.row.groupID, let folder = state.folders.first(where: { $0.id == groupID }) else {
            rowView.card = nil
            return
        }
        let last = lastShown(in: top)
        let piece: OutlineRowView.CardPiece = node === top ? (last === top ? .whole : .top) : node === last ? .bottom : .middle
        let fill = folder.tagValue.map { NSColor($0.color).withAlphaComponent(style.isDark ? 0.16 : 0.11) }
            ?? NSColor(colors.text).withAlphaComponent(style.isDark ? 0.06 : 0.04)
        rowView.card = (piece, fill)
        // The icon sidebar's tint sits behind its tile column only; the full sidebar's inside its margins.
        rowView.cardColumn = rail.map { ($0.inset, 36) }
        rowView.margin = rail == nil ? SidebarOutlineList.margin : 0
    }

    private func lastShown(in node: OutlineNode) -> OutlineNode {
        guard let last = node.children.last else { return node }
        return lastShown(in: last)
    }

    /// How far a row sits in from the list's edges for its place: inside a card a little, in folder style under its
    /// folder. The icon sidebar's tiles all sit in one column.
    private func insets(for node: OutlineNode) -> (leading: CGFloat, trailing: CGFloat) {
        guard rail == nil else { return (0, 0) }
        let margin = SidebarOutlineList.margin
        guard style.cards else { return (margin + CGFloat(node.depth) * 22, margin) }
        return node.parent == nil ? (margin, margin) : (margin + 4 + CGFloat(node.depth - 1) * 16, margin + 4)
    }

    /// The row's content, the same wherever it sits (its place is the cell's insets).
    /// `picture`: drawn into a picture (the lifted drag row), so AppKit-backed overlays (middle click, hover cards) stay out.
    private func content(for node: OutlineNode, picture: Bool = false) -> AnyView {
        var environment = environment
        if picture {
            environment.drawsPicture = true
            environment.tabHoverCards = false
        }
        if let rail {
            // Each tile measures itself in its own cell (`railSpace`); not in a picture, which can't draw its anchor.
            let tile = rail.cell(node.row).padding(.leading, rail.inset).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            let space = railSpaces[node.id] ?? {
                let space = RailSpace("rail.cell")
                space.surface = rail.space.surface
                railSpaces[node.id] = space
                return space
            }()
            if picture { return AnyView(tile.environment(\.self, environment)) }
            // A cell reused for another row is a new view: the tile it held leaves the hover effects' list.
            return AnyView(tile.railSpace(space).environment(\.self, environment).id(node.id))
        }
        let view: AnyView
        switch node.row.kind {
        case .tabs(let ids) where ids.count == 1:
            view = AnyView(OutlineTabRow(id: ids[0], state: state, chrome: chrome, colors: colors, commands: commands))
        case .tabs(let ids):
            view = AnyView(OutlineSplitRow(ids: ids, state: state, chrome: chrome, colors: colors, commands: commands))
        case .group(let id):
            view = AnyView(OutlineGroupHeader(id: id, state: state, chrome: chrome, colors: colors, commands: commands))
        case .divider:
            view = AnyView(OutlineNewTabRow(colors: colors) { [weak self] in self?.commands?.newTab() })
        case .essentials:
            view = AnyView(SidebarEssentials(state: state, chrome: chrome, commands: commands, onSelection: onSelection))
        }
        return AnyView(view.environment(\.self, environment))
    }

    // MARK: Clicks

    private func clicked(_ row: Int) {
        guard row >= 0, let node = outlineView.item(atRow: row) as? OutlineNode else { return }
        switch node.row.kind {
        case .tabs(let ids):
            guard let tab = state.tab(ids[0]) else { return }
            TabClick.handle(tab, state: state, chrome: chrome, commands: commands) { [weak self] in
                withAnimation(.ikago) { self?.state.select(tab.id) }
                self?.onSelection?()
            }
        case .group(let id):
            withAnimation(.groupDisclosure) { state.toggleFolder(id) }
        case .divider:
            commands?.newTab()
        case .essentials: break
        }
    }

    // MARK: Dragging out of the list

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> (any NSPasteboardWriting)? {
        guard let node = item as? OutlineNode else { return nil }
        let pasteboardItem = NSPasteboardItem()
        switch node.row.kind {
        case .tabs(let ids):
            guard let data = try? JSONEncoder().encode(TabDrag(id: ids[0])) else { return nil }
            pasteboardItem.setData(data, forType: NSPasteboard.PasteboardType(UTType.ikagoTab.identifier))
        case .group(let id):
            guard let data = try? JSONEncoder().encode(GroupDrag(id: id)) else { return nil }
            pasteboardItem.setData(data, forType: NSPasteboard.PasteboardType(UTType.ikagoGroup.identifier))
        case .divider, .essentials:
            return nil
        }
        return pasteboardItem
    }

    func outlineView(_ outlineView: NSOutlineView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint,
                     forItems draggedItems: [Any]) {
        let draggedNodes = draggedItems.compactMap { $0 as? OutlineNode }
        guard let first = draggedNodes.first else { return }
        // The same drag state the rest of the window uses: split targets on the page, tear-off, companions.
        switch first.row.kind {
        case .tabs(let ids): chrome.beginTabDrag(ids[0])
        case .group(let id): chrome.beginFolderDrag(id)
        case .divider, .essentials: break
        }
        // The icon sidebar's Magnify closes for the drag before the row's picture is taken (its rows covered the tiles).
        if rail != nil { chrome.rail.tick() }
        self.outlineView.dragStarted = true
        // The row itself, lifted: its picture with a soft shadow.
        session.enumerateDraggingItems(options: [], for: outlineView, classes: [NSPasteboardItem.self], searchOptions: [:]) { item, index, _ in
            guard index < draggedNodes.count else { return }
            let row = outlineView.row(forItem: draggedNodes[index])
            guard row >= 0, let rowView = outlineView.rowView(atRow: row, makeIfNecessary: false) else { return }
            // The row inside the sidebar's margins, as it shows.
            let shown = rowView.bounds.insetBy(dx: self.rowMargin, dy: 0)
            let image = self.lifted(draggedNodes[index], size: shown.size, scale: outlineView.window?.backingScaleFactor ?? 2)
            let frame = outlineView.convert(shown, from: rowView).insetBy(dx: -8, dy: -8)
            item.setDraggingFrame(frame, contents: image)
        }
    }

    /// A picture of the row raised off the list: the row on the sidebar's own surface, rounded, with a soft shadow.
    /// Drawn from its SwiftUI view: a snapshot of the hosting view (`cacheDisplay`) leaves out SwiftUI's text layers.
    /// The full sidebar's margins, which its list spans and its rows sit inside.
    private var rowMargin: CGFloat { rail == nil ? SidebarOutlineList.margin : 0 }

    private func lifted(_ node: OutlineNode, size: NSSize, scale: CGFloat) -> NSImage {
        let inset = insets(for: node)
        let renderer = ImageRenderer(content: content(for: node, picture: true)
            .padding(.leading, inset.leading - rowMargin).padding(.trailing, inset.trailing - rowMargin)
            .frame(width: size.width, height: size.height))
        renderer.scale = scale
        let picture = renderer.nsImage
        let padded = NSSize(width: size.width + 16, height: size.height + 16)
        let appearance = NSAppearance(named: style.scheme == .dark ? .darkAqua : .aqua)
        return NSImage(size: padded, flipped: false) { _ in
            let card = NSRect(x: 8, y: 8, width: size.width, height: size.height)
            let path = NSBezierPath(roundedRect: card, xRadius: Radius.row, yRadius: Radius.row)
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
            shadow.shadowBlurRadius = 8
            shadow.shadowOffset = NSSize(width: 0, height: -2)
            shadow.set()
            appearance?.performAsCurrentDrawingAppearance {
                NSColor.windowBackgroundColor.withAlphaComponent(0.96).setFill()
                path.fill()
            }
            NSGraphicsContext.restoreGraphicsState()
            path.addClip()
            picture?.draw(in: card)
            return true
        }
    }

    // MARK: Dropping in the list

    /// Where a drop is, from what the pointer is over on screen (the rows' rects include the open gap). Over the upper
    /// half of a row: before it. Over the lower half of a group's header: into the group. Over the lower half of a tab
    /// row, or in a gap: before the row below. Below every row: the end. The essentials row takes a drag only over its band
    /// (`SidebarEssentials.band`): its grid is a drop target of its own. AppKit offers each gap at the
    /// deepest level it could belong to (it tells levels apart by the pointer's x, and the rows have no indentation), so
    /// its proposal isn't used: one gap has one meaning, and a drop into a group shows as the group's highlight instead.
    private func target(_ info: any NSDraggingInfo) -> SidebarOutline.Target {
        let pointer = outlineView.convert(info.draggingLocation, from: nil)
        let count = outlineView.numberOfRows
        // Over the essentials floating at the top of the scrolled list: them, not the row hidden under them.
        let floating = floatingEssentials.flatMap { $0.rect.minY <= pointer.y && pointer.y < $0.rect.maxY ? $0 : nil }
        let row = floating?.row ?? outlineView.row(at: pointer)
        if row >= 0, let node = outlineView.item(atRow: row) as? OutlineNode {
            let rect = floating?.rect ?? outlineView.rect(ofRow: row)
            if let floating, SidebarEssentials.spot(inRow: CGPoint(x: pointer.x - rect.minX, y: pointer.y - rect.minY), width: rect.width, state) == .after {
                // Under the grid: before the first row the header doesn't cover.
                let below = (0..<count).first { outlineView.rect(ofRow: $0).minY >= floating.rect.maxY }
                return below.flatMap { outlineView.item(atRow: $0) as? OutlineNode }.map { .before($0.id) } ?? .end
            }
            if node.row.kind == .essentials {
                switch SidebarEssentials.spot(inRow: CGPoint(x: pointer.x - rect.minX, y: pointer.y - rect.minY), width: rect.width, state) {
                case .band: return .before(node.id)
                case .grid(let before): return .essential(before: before)
                case .after: break
                }
            } else if pointer.y < rect.midY {
                return .before(node.id)
            }
            if let group = node.row.groupID { return .into(group) }
            return row + 1 < count ? (outlineView.item(atRow: row + 1) as? OutlineNode).map { .before($0.id) } ?? .end : .end
        }
        let below = (0..<count).first { outlineView.rect(ofRow: $0).minY >= pointer.y }
        return below.flatMap { outlineView.item(atRow: $0) as? OutlineNode }.map { .before($0.id) } ?? .end
    }

    /// Shows where a drop lands: the group's highlight for a drop into it, the essentials' for one into them, else the
    /// gap among the rows on screen.
    private func showDrop(_ target: SidebarOutline.Target, moving: [SidebarOutline.Row]) {
        switch target {
        case .into(let group):
            outlineView.setDropItem(nodes["group:" + group], dropChildIndex: NSOutlineViewDropOnItemIndex)
            return
        case .essential:
            outlineView.setDropItem(nodes["essentials"], dropChildIndex: NSOutlineViewDropOnItemIndex)
            return
        case .before, .end:
            break
        }
        guard let place = state.sidebarOutline.place(for: moving, at: target) else { return }
        let ids = Set(moving.map(\.id))
        let staying = (state.sidebarOutline.rows(in: place.parent) ?? []).filter { !ids.contains($0.id) }
        let parent = place.parent.flatMap { nodes["group:" + $0] }
        let shown = children(of: parent)
        // The first row it goes before that the list shows (the icon sidebar leaves some out).
        let next = staying.dropFirst(place.index).lazy.compactMap { row in shown.firstIndex { $0.id == row.id } }.first
        outlineView.setDropItem(parent, dropChildIndex: next ?? shown.count)
    }

    func outlineView(_ outlineView: NSOutlineView, validateDrop info: any NSDraggingInfo, proposedItem item: Any?,
                     proposedChildIndex index: Int) -> NSDragOperation {
        updateDrop(info)
    }

    /// Where the drag in progress lands, as its gap shows it, and whether it may. The drop goes there: when AppKit
    /// hands the drop over, the gap may be closing and the rows under the pointer moving back.
    private var shownDrop: (drag: Int, target: SidebarOutline.Target, operation: NSDragOperation)?

    /// Asks the model where the drag lands for the pointer now and shows it. AppKit asks (`validateDrop`) only when its
    /// own guess at the place changes, having put its guess in place; the place depends on the pointer, so the outline
    /// asks on every move too (`SidebarOutlineTable.draggingUpdated`), and the place is set every time.
    @discardableResult
    func updateDrop(_ info: any NSDraggingInfo) -> NSDragOperation {
        let target = target(info)
        let moving = draggedRows(info, includingCompanions: false)
        var operation: NSDragOperation = []
        if state.acceptsSidebarRows(moving, at: target) {
            showDrop(target, moving: moving)
            operation = .move
        }
        shownDrop = (info.draggingSequenceNumber, target, operation)
        return operation
    }

    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: any NSDraggingInfo, item: Any?, childIndex: Int) -> Bool {
        takeDrop(info)
    }

    /// Takes a drop where its gap showed it; also one AppKit refused because it skipped asking while only the pointer
    /// moved (`SidebarOutlineTable.performDragOperation`). The gap goes first (AppKit's record of it pointed at rows
    /// that then moved, and a later drag crashed in AppKit), then the rows move straight to its place.
    func takeDrop(_ info: any NSDraggingInfo) -> Bool {
        guard let shown = shownDrop, shown.drag == info.draggingSequenceNumber else { return false }
        shownDrop = nil
        let moving = draggedRows(info, includingCompanions: true)
        chrome.endTabDrag()
        chrome.endFolderDrag()
        chrome.selectedTabIDs = []
        // The gap closes at once, with the motion of its opening or closing still on the rows: a moved row would keep
        // sliding along that path from its old place.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            outlineView.setDropItem(nil, dropChildIndex: NSOutlineViewDropOnItemIndex)
            outlineView.layoutSubtreeIfNeeded()
        }
        outlineView.enumerateAvailableRowViews { rowView, _ in rowView.layer?.removeAnimation(forKey: "position") }
        guard shown.operation == .move, state.acceptsSidebarRows(moving, at: shown.target) else { return false }
        takenDrop = (moving, shown.target)
        return true
    }

    /// A drop taken, its rows not moved yet: they move once AppKit is done with the drag (`dropFinished`).
    private var takenDrop: (moving: [SidebarOutline.Row], target: SidebarOutline.Target)?
    /// The model changed while a drag from this list was under way: the list shows it when the drag ends.
    private var heldWhileDragging = false

    /// AppKit is done with the drag: the dropped rows move now, straight to their place. A drag from this list ends
    /// last as its source (`draggingSession(_:endedAt:operation:)`): AppKit gives the dragged row its space back there by
    /// its old row, and rows moved before that crashed it.
    func dropFinished() {
        var changed = heldWhileDragging
        heldWhileDragging = false
        if let (moving, target) = takenDrop {
            takenDrop = nil
            changed = state.moveSidebarRows(moving, to: target) || changed
        }
        if changed { show(SidebarOutlineList.shown(state, rail: rail), style: style, animated: false) }
    }

    /// The rows a drag carries: a group, or a tab's row with the selected tabs travelling with it (brought into this
    /// window first when they come from another).
    private func draggedRows(_ info: any NSDraggingInfo, includingCompanions: Bool) -> [SidebarOutline.Row] {
        let pasteboard = info.draggingPasteboard
        if let data = pasteboard.data(forType: NSPasteboard.PasteboardType(UTType.ikagoGroup.identifier)),
           let drag = try? JSONDecoder().decode(GroupDrag.self, from: data) {
            return state.sidebarRows(group: drag.id)
        }
        guard let data = pasteboard.data(forType: NSPasteboard.PasteboardType(UTType.ikagoTab.identifier)),
              let drag = try? JSONDecoder().decode(TabDrag.self, from: data) else { return [] }
        guard includingCompanions else { return state.sidebarRows(dragging: [drag.id]) }
        let travelling = TabDrag.travelling(with: drag.id)
        for id in travelling { BrowserWindows.bring(id, into: state) }
        return state.sidebarRows(dragging: travelling)
    }

    #if DEBUG
    /// Every list alive; `shown(in:)` is the one in that window's sidebar (not the copy Expand draws over the rail).
    static let made = NSHashTable<SidebarOutlineController>.weakObjects()
    static func shown(in window: NSWindow?) -> SidebarOutlineController? {
        made.allObjects.first { $0.outlineView.window === window && $0.outlineView.window != nil }
    }
    func liftedImage(row: Int) -> NSImage? {
        guard let node = outlineView.item(atRow: row) as? OutlineNode, node.row.kind != .divider else { return nil }
        guard let rowView = outlineView.rowView(atRow: row, makeIfNecessary: false) else { return nil }
        return lifted(node, size: rowView.bounds.insetBy(dx: rowMargin, dy: 0).size, scale: outlineView.window?.backingScaleFactor ?? 2)
    }
    func nodeForCheck(_ id: String) -> OutlineNode? { nodes[id] }
    func heightForCheck(_ node: OutlineNode) -> CGFloat { height(of: node) }
    /// Where the drag in progress would land now, as its gap shows it.
    var shownDropForCheck: SidebarOutline.Target? { shownDrop?.target }
    /// What the list should show now: the model's rows as this list shows them.
    var expectedOutlineForCheck: SidebarOutline { SidebarOutlineList.shown(state, rail: rail) }
    /// A row's indent and card piece now, for checks that a moved row looks like its new place.
    func placeForCheck(_ id: String) -> (leading: CGFloat, card: OutlineRowView.CardPiece?)? {
        guard let node = nodes[id] else { return nil }
        let row = outlineView.row(forItem: node)
        guard row >= 0, let cell = outlineView.view(atColumn: 0, row: row, makeIfNecessary: false) as? OutlineHostingCell else { return nil }
        let rowView = outlineView.rowView(atRow: row, makeIfNecessary: false) as? OutlineRowView
        return (cell.insets.leading, rowView?.card?.piece)
    }
    #endif
}

extension SidebarOutlineList {
    /// How far the full sidebar's list reaches past its rows on each side (`SidebarView`'s margins).
    static let margin: CGFloat = 10
}
