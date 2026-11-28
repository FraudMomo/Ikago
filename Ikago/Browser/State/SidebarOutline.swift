import Foundation

/// The sidebar's list as a tree of rows, and the one rule for where a dragged row lands.
///
/// Top level, in order: the pinned rows above the essentials, the essentials' own row (the grid); the block (pinned rows,
/// and the groups kept above the tabs with the pins placed after each), the divider (the New Tab line), then the loose
/// tabs with the groups placed among them. Everything above the divider is pinned: its tabs, and its groups' tabs, stay
/// when closed. A group's rows are its
/// groups, then its tabs. Split tabs are one row. The outline always holds every row; a view leaves out what it doesn't
/// show (the divider when New Tab is off, the loose tabs under Top Tabs, the icon sidebar's pins). The sidebar shows the
/// essentials as one row of the list, so a row goes above or below them like anywhere else.
///
/// A move is three steps, all here: `place(for:at:)` says where rows dropped at a target land, `moving(_:to:)` is the
/// outline with them there, and `BrowserState.apply(_:)` writes an outline back to the tabs and groups.
struct SidebarOutline: Equatable {
    struct Row: Identifiable, Equatable {
        enum Kind: Equatable {
            /// A tab, or a split pair/group of tabs shown as one row.
            case tabs([String])
            case group(String)
            /// The line (and New Tab row) between the block and the loose tabs.
            case divider
            /// The essentials' grid: pinned rows before it sit above it. Never moved: always the first row after the pins
            /// above it.
            case essentials
        }
        let kind: Kind
        var children: [Row] = []
        /// A group shown open.
        var isOpen = false

        var id: String {
            switch kind {
            case .tabs(let ids): (ids.count == 1 ? "tab:" : "split:") + ids.joined(separator: ",")
            case .group(let id): "group:" + id
            case .divider: "divider"
            case .essentials: "essentials"
            }
        }
        var tabIDs: [String] {
            switch kind {
            case .tabs(let ids): ids
            case .group: children.flatMap(\.tabIDs)
            case .divider, .essentials: []
            }
        }
        var groupID: String? { if case .group(let id) = kind { id } else { nil } }
    }

    var rows: [Row]

    /// Every tab in list order.
    var tabOrder: [String] { rows.flatMap(\.tabIDs) }

    /// The row with this id, at any depth.
    func row(_ id: String) -> Row? { Self.find(in: rows) { $0.id == id } }

    /// The rows directly under a group (nil: the top level); nil when the group isn't in the list.
    func rows(in group: String?) -> [Row]? {
        guard let group else { return rows }
        return Self.find(in: rows) { $0.groupID == group }?.children
    }

    /// Where a row sits: its group (nil: the top level) and its index there.
    func location(of id: String) -> (parent: String?, index: Int)? {
        func search(_ list: [Row], _ parent: String?) -> (String?, Int)? {
            for (index, row) in list.enumerated() {
                if row.id == id { return (parent, index) }
                if let found = search(row.children, row.groupID) { return found }
            }
            return nil
        }
        return search(rows, nil).map { (parent: $0.0, index: $0.1) }
    }

    private static func find(in rows: [Row], _ match: (Row) -> Bool) -> Row? {
        for row in rows {
            if match(row) { return row }
            if let found = find(in: row.children, match) { return found }
        }
        return nil
    }

    // MARK: Dropping

    /// Where a drop is in the list: in a gap, before the row below it (or below every row), or onto a group.
    enum Target: Equatable {
        case before(String)
        /// Into this group: first when it is open (AppKit shows the gap under its header), last when it is shut.
        case into(String)
        case end
        /// Into the essentials grid, before this tile (nil: last). Tabs only: not a row of the list.
        case essential(before: String?)
    }

    /// Where moving rows land: under `parent` (nil: the top level), at `index` among the rows that stay there.
    struct Place: Equatable {
        var parent: String?
        var index: Int
    }

    /// The one rule for drops: where `moving` lands when dropped at `target`, or nil when it can't go there (a group
    /// into itself, a group above the essentials grid). Rows that aren't in the outline yet (from another window, the pin
    /// grid) are welcome. Inside a group its groups come first, then its tabs, so a row lands at the nearest place its
    /// kind can be.
    func place(for moving: [Row], at target: Target) -> Place? {
        let ids = Set(moving.map(\.id))
        let movingGroups = Set(moving.compactMap(\.groupID))
        // The target as a place among the rows as they are now (the moving ones still in).
        var parent: String?, index: Int
        switch target {
        case .end:
            (parent, index) = (nil, rows.count)
        case .before(let id):
            guard let at = location(of: id) else { return nil }
            (parent, index) = (at.parent, at.index)
        case .into(let id):
            guard let group = row("group:" + id) else { return nil }
            (parent, index) = (id, group.isOpen ? 0 : group.children.count)
        case .essential:
            return nil
        }
        // Never into a moving group or a group inside one.
        var ancestor = parent
        while let id = ancestor {
            if movingGroups.contains(id) { return nil }
            ancestor = location(of: "group:" + id)?.parent
        }
        // The same place among the rows that stay.
        let siblings = rows(in: parent) ?? []
        let staying = siblings.filter { !ids.contains($0.id) }
        index = siblings.prefix(index).filter { !ids.contains($0.id) }.count
        if parent != nil {
            let groups = staying.prefix { $0.groupID != nil }.count
            index = movingGroups.isEmpty ? max(index, groups) : min(index, groups)
        } else if !movingGroups.isEmpty, let grid = staying.firstIndex(where: { $0.kind == .essentials }), index <= grid {
            return nil
        }
        return Place(parent: parent, index: index)
    }

    /// The outline with `moving` taken from wherever they are and put at `place`, in their order.
    func moving(_ moving: [Row], to place: Place) -> SidebarOutline {
        let ids = Set(moving.map(\.id))
        // The moving rows as they are in the list (a group with its rows), or as given when they're new to it.
        let carried = moving.map { row($0.id) ?? $0 }
        func without(_ list: [Row]) -> [Row] {
            list.compactMap { row in
                guard !ids.contains(row.id) else { return nil }
                var row = row
                row.children = without(row.children)
                return row
            }
        }
        func inserting(_ list: [Row], under parent: String?) -> [Row] {
            if parent == place.parent {
                var list = list
                list.insert(contentsOf: carried, at: min(place.index, list.count))
                return list
            }
            return list.map { row in
                var row = row
                if row.groupID != nil { row.children = inserting(row.children, under: row.groupID) }
                return row
            }
        }
        return SidebarOutline(rows: inserting(without(rows), under: nil))
    }
}

extension BrowserState {
    /// Every row the sidebar can list in the active Space, open groups marked.
    var sidebarOutline: SidebarOutline {
        let shown = shownFolderIDs
        let rowPins = pinnedTabs.filter { !presentsSidebarPinGrid || $0.pinAsRow || splitGroup(of: $0.id) != nil }
        let anchors = Dictionary(grouping: rowPins.filter { !$0.pinAboveGrid }) { tab in tab.pinAfterFolderID.flatMap { shown.contains($0) ? $0 : nil } ?? "" }
        var seen = Set<String>()

        func tabRows(_ list: [TabItem]) -> [SidebarOutline.Row] {
            listItems(list, seen: &seen).map { item in
                switch item {
                case .tab(let tab): SidebarOutline.Row(kind: .tabs([tab.id]))
                case .group(let tabs): SidebarOutline.Row(kind: .tabs(tabs.map(\.id)))
                }
            }
        }
        func groupRow(_ folder: TabFolder, depth: Int) -> SidebarOutline.Row {
            var children: [SidebarOutline.Row] = []
            if depth < 8 {
                for child in childFolders(of: folder.id) where shown.contains(child.id) {
                    children.append(groupRow(child, depth: depth + 1))
                }
            }
            children += tabRows(tabs(in: folder))
            return SidebarOutline.Row(kind: .group(folder.id), children: children, isOpen: folder.isOpen)
        }

        // Pinned rows above the essentials, then the essentials' own row.
        var rows = tabRows(rowPins.filter(\.pinAboveGrid))
        rows.append(SidebarOutline.Row(kind: .essentials))
        rows += tabRows(anchors[""] ?? [])
        for folder in blockFolders {
            rows.append(groupRow(folder, depth: 0))
            // Pins placed after this group follow it.
            rows += tabRows(anchors[folder.id] ?? [])
        }
        rows.append(SidebarOutline.Row(kind: .divider))
        for entry in looseEntries {
            switch entry {
            case .tab(let tab): rows += tabRows([tab])
            case .folder(let folder): rows.append(groupRow(folder, depth: 0))
            }
        }
        return SidebarOutline(rows: rows)
    }

    /// The rows a drag carries: the group, or the tab's row (its split row when it has one) with the selected tabs
    /// travelling with it, from this list or from anywhere else.
    func sidebarRows(dragging tabIDs: [String] = [], group: String? = nil) -> [SidebarOutline.Row] {
        let outline = sidebarOutline
        if let group { return [outline.row("group:" + group) ?? SidebarOutline.Row(kind: .group(group))] }
        var rows: [SidebarOutline.Row] = []
        for id in tabIDs where !rows.contains(where: { $0.tabIDs.contains(id) }) {
            let ids = splitGroup(of: id) ?? [id]
            rows.append(SidebarOutline.Row(kind: .tabs(ids)))
        }
        return rows
    }

    /// Whether rows dropped at `target` go anywhere: the essentials take single tabs (a split stays a row), a row of the
    /// list the place the one rule gives (`SidebarOutline.place`).
    func acceptsSidebarRows(_ moving: [SidebarOutline.Row], at target: SidebarOutline.Target) -> Bool {
        guard !moving.isEmpty else { return false }
        switch target {
        case .essential:
            return moving.allSatisfy { row in if case .tabs(let ids) = row.kind { ids.count == 1 } else { false } }
        case .before, .into, .end:
            return sidebarOutline.place(for: moving, at: target) != nil
        }
    }

    /// Moves rows to where they land at `target`; false when they can't go there. Into the essentials a tab becomes one
    /// of them, before the tile named. In the list, rows go where the one rule says
    /// (`SidebarOutline.place`), and a group a row is dropped into opens, so the row stays on screen.
    @discardableResult
    func moveSidebarRows(_ moving: [SidebarOutline.Row], to target: SidebarOutline.Target) -> Bool {
        guard acceptsSidebarRows(moving, at: target) else { return false }
        switch target {
        case .essential(let before):
            for id in moving.flatMap(\.tabIDs) {
                movePin(id, intoGrid: true)
                if let before, before != id, tab(before)?.pinned == true { move(id, before: before, pinned: true) }
            }
            scheduleSave()
            return true
        case .before, .into, .end:
            break
        }
        let outline = sidebarOutline
        guard let place = outline.place(for: moving, at: target) else { return false }
        apply(outline.moving(moving, to: place))
        var next = place.parent, steps = 0
        while let id = next, steps < 16, let index = folders.firstIndex(where: { $0.id == id }) {
            folders[index].isOpen = true
            next = folders[index].parentID
            steps += 1
        }
        scheduleSave()
        return true
    }

    /// Writes an outline back: every tab and group in it becomes what its place holds. Above the essentials grid tabs are
    /// pinned rows above it; above the divider tabs are pinned rows (placed after the group before them) and groups sit
    /// in the block; below it tabs are loose and groups
    /// sit after the loose tab before them; inside a group tabs join it and groups nest. Tabs and groups the outline
    /// doesn't hold (other Spaces, the pin grid, hidden groups) keep their places.
    func apply(_ outline: SidebarOutline) {
        let tabOrder = outline.tabOrder
        // Hidden groups placed after a loose tab that stops being loose stay where they are.
        var loose = Set<String>()
        var inBlock = true
        for row in outline.rows {
            if row.kind == .divider { inBlock = false } else if !inBlock, case .tabs(let ids) = row.kind { loose.formUnion(ids) }
        }
        for tab in looseTabs where !loose.contains(tab.id) { keepGroupsInPlace(leaving: tab.id) }

        var groupOrder: [String] = []
        func place(_ id: String, parent: String?, after anchor: String?) {
            guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
            folders[index].parentID = parent
            folders[index].afterTabID = anchor
            groupOrder.append(id)
        }
        func member(_ id: String, of group: String) {
            guard let tab = tab(id) else { return }
            tab.pinned = false; tab.pinAsRow = false; tab.pinAfterFolderID = nil; tab.pinAboveGrid = false; tab.folderID = group
        }
        func fill(_ group: SidebarOutline.Row) {
            guard let id = group.groupID else { return }
            for row in group.children {
                if let child = row.groupID {
                    place(child, parent: id, after: nil)
                    fill(row)
                } else {
                    row.tabIDs.forEach { member($0, of: id) }
                }
            }
        }
        inBlock = true
        var aboveGrid = outline.rows.contains { $0.kind == .essentials }
        var lastGroup: String?, lastLoose = ""
        for row in outline.rows {
            switch row.kind {
            case .essentials:
                aboveGrid = false
            case .divider:
                inBlock = false
            case .group(let id):
                place(id, parent: nil, after: inBlock ? nil : lastLoose)
                if inBlock { lastGroup = id }
                fill(row)
            case .tabs(let ids):
                for id in ids {
                    guard let tab = tab(id) else { continue }
                    tab.folderID = nil
                    tab.pinned = inBlock
                    tab.pinAsRow = inBlock
                    tab.pinAfterFolderID = inBlock && !aboveGrid ? lastGroup : nil
                    tab.pinAboveGrid = inBlock && aboveGrid
                    if !inBlock { lastLoose = id }
                }
            }
        }
        tabs = Self.ordered(tabs, by: tabOrder, id: \.id)
        tabs = tabs.filter(\.pinned) + tabs.filter { !$0.pinned }
        folders = Self.ordered(folders, by: groupOrder, id: \.id)
    }

    /// `list` with the items named in `order` put in that order, in the places those items held; every other item
    /// stays where it is.
    private static func ordered<T>(_ list: [T], by order: [String], id: KeyPath<T, String>) -> [T] {
        let byID = Dictionary(list.map { ($0[keyPath: id], $0) }, uniquingKeysWith: { first, _ in first })
        let present = order.filter { byID[$0] != nil }
        let wanted = Set(present)
        var next = present.makeIterator()
        return list.map { item in wanted.contains(item[keyPath: id]) ? next.next().flatMap { byID[$0] } ?? item : item }
    }
}
