import AppKit
import SwiftUI

/// What the icon sidebar's hover effects draw over the window (`RailHover`): Magnify's pills and group islands, or
/// Expand's full sidebar. One layer above the page, so the rail itself never changes size or moves.
struct RailHoverLayers: View {
    let state: BrowserState
    let chrome: ChromeModel
    let palette: CommandPaletteModel
    weak var commands: BrowserCommands?

    var body: some View {
        switch state.browserPreferences.railHover {
        case .magnify: RailMagnifyLayer(state: state, model: chrome.rail, commands: commands)
        case .expand: RailExpandPanel(state: state, chrome: chrome, commands: commands)
        case nil: EmptyView()
        }
    }
}

// MARK: - Magnify

private struct RailMagnifyLayer: View {
    let state: BrowserState
    let model: RailHoverModel
    weak var commands: BrowserCommands?

    var body: some View {
        GeometryReader { geometry in
            let space = LayerSpace(origin: geometry.frame(in: .global).origin, model: model)
            let _ = model.scrolled
            // While an island is open the pills give way to it.
            let pointerY = model.island == nil ? space.y(of: model.pointer) : nil
            let rects = Dictionary(uniqueKeysWithValues: model.tiles.keys.compactMap { tile in space.rect(tile).map { (tile, $0) } })
            // The leading row: the tile nearest the pointer, when the pointer is on or beside it (not between far rows).
            let lead = pointerY.flatMap { y in
                rects.min { abs($0.value.midY - y) < abs($1.value.midY - y) }.flatMap { abs($0.value.midY - y) < $0.value.height / 2 + 4 ? $0.key : nil }
            }
            ZStack(alignment: .topLeading) {
                ForEach(Array(rects.keys), id: \.self) { tile in
                    if let rect = rects[tile], let name = name(of: tile) {
                        let extra = pointerY.map { RailHover.reachOut(nameWidth: RailHover.nameWidth(name), distance: rect.midY - $0) } ?? 0
                        RailPill(tile: tile, name: name, size: rect.size, extra: extra, leads: tile == lead, state: state, model: model,
                                 commands: commands)
                            .offset(x: state.sidebarOnRight ? rect.maxX - rect.width - extra : rect.minX, y: rect.minY)
                            .zIndex(tile == lead ? 1 : 0)
                    }
                }
                if let id = model.island, let folder = state.folders.first(where: { $0.id == id }), let rect = space.rect(.folder(id)) {
                    RailIsland(folder: folder, tile: rect, room: geometry.size.height - rect.maxY - 12, state: state, model: model,
                               commands: commands)
                        .id(id)
                        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: state.sidebarOnRight ? .topTrailing : .topLeading)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func name(of tile: RailHoverModel.Tile) -> String? {
        switch tile {
        case .tab(let id): state.tab(id)?.displayTitle
        case .folder(let id): state.folders.first { $0.id == id }?.name
        }
    }
}

/// Converts the rail's window coordinates (AppKit's, from the bottom) into the layer's (from its top-left).
@MainActor
private struct LayerSpace {
    let origin: CGPoint
    let model: RailHoverModel

    private var height: CGFloat? {
        model.tiles.values.lazy.compactMap { $0.space.view?.window?.contentView?.bounds.height }.first
    }

    func rect(_ tile: RailHoverModel.Tile) -> CGRect? {
        guard let height, let rect = model.windowRect(tile) else { return nil }
        return CGRect(x: rect.minX - origin.x, y: height - rect.maxY - origin.y, width: rect.width, height: rect.height)
    }

    func y(of point: NSPoint?) -> CGFloat? {
        guard let point, let height else { return nil }
        return height - point.y - origin.y
    }
}

/// A row reaching out past the rail. The row under the pointer leads: a raised card with its icon, its name and its
/// site (a group: how many tabs it holds), which takes clicks where it reaches over the page and keeps the rows still
/// while the pointer is on it, so the pointer can cross onto it. Its neighbours show the same card flat and faded, their
/// names dimmer the further they are; they shorten back into their tiles as the pointer moves off.
private struct RailPill: View {
    let tile: RailHoverModel.Tile
    let name: String
    let size: CGSize
    let extra: CGFloat
    let leads: Bool
    let state: BrowserState
    let model: RailHoverModel
    weak var commands: BrowserCommands?

    var body: some View {
        let colors = state.palette
        let shape = RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
        let onRight = state.sidebarOnRight
        let reach = min(1, extra / RailHover.profile)
        HStack(spacing: 2) {
            if onRight { label(colors, reach: reach) }
            // A faded card lets its tile's own icon show through; the leading card covers the tile, so it draws the icon.
            RailTileIcon(tile: tile, state: state).frame(width: size.width, height: size.height).opacity(leads ? 1 : 0)
            if !onRight { label(colors, reach: reach) }
        }
        .frame(width: size.width + extra, height: size.height, alignment: onRight ? .trailing : .leading)
        // A name longer than its row fades out at the end rather than being cut.
        .mask {
            HStack(spacing: 0) {
                if onRight { LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing).frame(width: 18) }
                Rectangle()
                if !onRight { LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 18) }
            }
            .padding(onRight ? .leading : .trailing, 4)
        }
        // The leading row's card is raised; its neighbours' are the same card, flat and faded, so they read as context.
        .background(RailPillSurface(colors: colors, shape: shape, active: active, lift: leads ? 7 : 0).opacity(leads ? 1 : 0.5))
        .opacity(min(1, extra / 18))
        .animation(RailHover.follow, value: extra)
        .animation(.easeOut(duration: 0.12), value: leads)
        // Clicks on the part over the page; the tile itself keeps its own (its menu, its drags).
        .contentShape(ReachShape(tile: size.width, onRight: onRight))
        .onTapGesture { open() }
        .contextMenu { menu }
        .background { if leads { RailPointerTracker { model.pillHover($0 != nil) } } }
        .allowsHitTesting(leads)
        .help(leads ? name : "")
    }

    private func label(_ colors: Palette, reach: CGFloat) -> some View {
        VStack(alignment: state.sidebarOnRight ? .trailing : .leading, spacing: 0) {
            Text(name)
                .font(.system(size: RailHover.nameSize, weight: leads ? .semibold : .regular))
                .foregroundStyle(leads ? colors.text : colors.text.opacity(0.35 + 0.4 * reach))
            if leads, let detail {
                Text(detail).font(.system(size: 10.5)).foregroundStyle(colors.secondary)
            }
        }
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 6)
    }

    private func open() {
        switch tile {
        case .tab(let id): state.select(id)
        case .folder(let id): model.toggleIsland(id)
        }
    }

    @ViewBuilder private var menu: some View {
        switch tile {
        case .tab(let id): if let tab = state.tab(id) { TabContextMenu(tab: tab, state: state, commands: commands) }
        case .folder(let id): if let folder = state.folders.first(where: { $0.id == id }) { FolderContextMenu(folder: folder, state: state, commands: commands) }
        }
    }

    private var detail: String? {
        switch tile {
        case .tab(let id):
            guard let tab = state.tab(id), let host = URL(string: tab.url)?.host() else { return nil }
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        case .folder(let id):
            guard let folder = state.folders.first(where: { $0.id == id }) else { return nil }
            let count = state.tabs(inSubtree: folder).count
            return "\(count) \(count == 1 ? "tab" : "tabs")"
        }
    }

    private var active: Bool {
        if case .tab(let id) = tile { return id == state.activeTabID }
        return false
    }
}

/// The part of a row past its tile: where the leading card takes clicks.
private struct ReachShape: Shape {
    let tile: CGFloat
    let onRight: Bool
    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: onRight ? rect.minX : rect.minX + tile, y: rect.minY, width: max(0, rect.width - tile), height: rect.height))
    }
}

/// The pills' and islands' card: solid (glass over a page washes out to white), with a hairline rim and a soft shadow.
private struct RailPillSurface<S: InsettableShape>: View {
    let colors: Palette
    let shape: S
    var active = false
    var lift: CGFloat = 7

    var body: some View {
        shape.fill(ModalMetrics.card(colors))
            .overlay { if active { shape.fill(colors.selected) } }
            .overlay(shape.strokeBorder(colors.isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.08), lineWidth: 0.5))
            .background { if lift > 0 { CardShadow(shape: shape, color: .black.opacity(colors.isDark ? 0.35 : 0.12), radius: lift, y: lift / 3) } }
    }
}

/// The icon a rail tile shows, for the pills and the islands.
private struct RailTileIcon: View {
    let tile: RailHoverModel.Tile
    let state: BrowserState

    var body: some View {
        switch tile {
        case .tab(let id):
            if let tab = state.tab(id) { FaviconView(tab: tab, size: tab.pinned ? 18 : 16) }
        case .folder(let id):
            if let folder = state.folders.first(where: { $0.id == id }) { FolderIcon(folder: folder, colors: state.palette, size: 15) }
        }
    }
}

// MARK: - Islands

/// A closed group's island: its name reaching out of its tile, and beside the rail a card with what it holds, the
/// groups inside it as a tree. It stays while the pointer is on it; a tab opens with a click.
private struct RailIsland: View {
    let folder: TabFolder
    let tile: CGRect
    /// Height left under the tile for the card.
    let room: CGFloat
    let state: BrowserState
    let model: RailHoverModel
    weak var commands: BrowserCommands?

    static let cardWidth: CGFloat = 240

    var body: some View {
        let colors = state.palette
        let onRight = state.sidebarOnRight
        let width = tile.width + 8 + Self.cardWidth
        VStack(alignment: onRight ? .trailing : .leading, spacing: 4) {
            header(colors)
            card(colors)
                .padding(onRight ? .trailing : .leading, tile.width + 8)
        }
        .frame(width: width, alignment: onRight ? .trailing : .leading)
        .onHover { model.islandHover($0) }
        .offset(x: onRight ? tile.maxX - width : tile.minX, y: tile.minY)
    }

    private func header(_ colors: Palette) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
        let count = state.tabs(inSubtree: folder).count
        return Button {
            // The island's name covers the group's tile, so a second click on the tile lands here: it closes the island.
            model.closeIsland()
        } label: {
            HStack(spacing: 2) {
                FolderIcon(folder: folder, colors: colors, size: 15).frame(width: tile.width, height: tile.height)
                Text(folder.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(colors.text).lineLimit(1)
                Text("\(count)").font(.system(size: 11, weight: .medium).monospacedDigit()).foregroundStyle(colors.tertiary)
                    .padding(.leading, 4)
            }
            .padding(.trailing, 12)
            .frame(height: tile.height)
            .environment(\.layoutDirection, state.sidebarOnRight ? .rightToLeft : .leftToRight)
            .background(RailPillSurface(colors: colors, shape: shape))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .help("Close \(folder.name)")
        .contextMenu { FolderContextMenu(folder: folder, state: state, commands: commands) }
    }

    private func card(_ colors: Palette) -> some View {
        let rows = RailIslandTree(parent: folder, depth: 0, state: state, model: model, commands: commands)
            .padding(6)
            .frame(width: Self.cardWidth, alignment: .leading)
        return ViewThatFits(in: .vertical) {
            rows
            ScrollView { rows }.scrollIndicators(.never)
        }
        .frame(maxHeight: max(80, room))
        .fixedSize(horizontal: false, vertical: true)
        .background(RailPillSurface(colors: colors, shape: RoundedRectangle(cornerRadius: Radius.card, style: .continuous), lift: 16))
    }
}

/// One level of an island's tree: the groups inside `parent`, each opening in place, then its tabs.
private struct RailIslandTree: View {
    let parent: TabFolder
    let depth: Int
    let state: BrowserState
    let model: RailHoverModel
    weak var commands: BrowserCommands?
    @State private var shut: Set<String> = []

    var body: some View {
        let colors = state.palette
        let children = state.childFolders(of: parent.id)
        let tabs = state.tabs(in: parent)
        VStack(alignment: .leading, spacing: 1) {
            ForEach(children) { child in
                let open = !shut.contains(child.id)
                RailIslandRow(depth: depth, colors: colors, active: false) {
                    if open { shut.insert(child.id) } else { shut.remove(child.id) }
                } label: {
                    Image(systemName: "chevron.right").font(.system(size: 8.5, weight: .bold)).foregroundStyle(colors.tertiary)
                        .rotationEffect(.degrees(open ? 90 : 0)).frame(width: 10)
                    FolderIcon(folder: child, colors: colors, size: 13).frame(width: 18)
                    Text(child.name).font(.system(size: 12.5, weight: .medium))
                }
                .contextMenu { FolderContextMenu(folder: child, state: state, commands: commands) }
                if open {
                    RailIslandTree(parent: child, depth: depth + 1, state: state, model: model, commands: commands)
                        .transition(.opacity)
                }
            }
            ForEach(tabs) { tab in
                RailIslandRow(depth: depth, colors: colors, active: tab.id == state.activeTabID) {
                    model.closeIsland()
                    state.select(tab.id)
                } label: {
                    Color.clear.frame(width: 10)
                    FaviconView(tab: tab, size: 14).opacity(tab.isUnloaded ? 0.55 : 1).frame(width: 18)
                    Text(tab.displayTitle).font(.system(size: 12.5))
                }
                .contextMenu { TabContextMenu(tab: tab, state: state, commands: commands) }
            }
            if children.isEmpty && tabs.isEmpty && depth == 0 {
                Text("No tabs").font(.system(size: 12)).foregroundStyle(colors.tertiary).padding(8)
            }
        }
        .animation(RailHover.reveal, value: shut)
    }
}

private struct RailIslandRow<Label: View>: View {
    let depth: Int
    let colors: Palette
    let active: Bool
    let action: () -> Void
    @ViewBuilder let label: Label
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.inner + 1, style: .continuous)
        Button(action: action) {
            HStack(spacing: 6) { label }
                .foregroundStyle(colors.text)
                .lineLimit(1)
                .padding(.leading, 6 + CGFloat(depth) * 14)
                .padding(.trailing, 8)
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                .background(shape.fill(active ? colors.selected : colors.text.opacity(hovering ? 0.07 : 0)))
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Expand

/// Expand: the rail itself grows wider over the page while the pointer is on it, every item where it was and each
/// row's name beside its icon (`SidebarRail(expanded:)`, the rail's own layout). It is laid out at its full width the
/// whole time and only its clip moves, from the rail's edge out and back, so nothing reflows while it grows. It stays
/// mounted and hidden while Expand is on, so it is whole on the first frame.
private struct RailExpandPanel: View {
    let state: BrowserState
    let chrome: ChromeModel
    weak var commands: BrowserCommands?

    var body: some View {
        let model = chrome.rail
        GeometryReader { geometry in
            let origin = geometry.frame(in: .global).origin
            let out = model.expanded
            if let rail = model.railRect(from: origin) {
                let width = RailHover.expandedWidth
                let onRight = state.sidebarOnRight
                let shape = RoundedRectangle(cornerRadius: state.sidebarJoinsWindow ? Radius.card : Radius.card + 4, style: .continuous)
                SidebarRail(state: state, chrome: chrome, commands: commands, expanded: true)
                    .frame(width: width, height: rail.height)
                    // The rail's own look: the window's color where it joins the window, its glass panel over that
                    // color otherwise (glass alone would show the page through).
                    .background {
                        ZStack {
                            shape.fill(state.palette.tint)
                            // Glass on, the rail's glass panel over that color, as the docked rail is.
                            if !state.sidebarJoinsWindow {
                                Color.clear.surface(shape, state.palette, translucentSidebar: state.browserPreferences.translucentSidebar == true)
                            }
                        }
                        .background(CardShadow(shape: shape, color: .black.opacity(state.isDark ? 0.4 : 0.16), radius: 14, x: 2))
                    }
                    // Only the edge moves: out from the rail's on a spring, back to it a little quicker. At the rail's
                    // width it looks just like the rail, so it shows and hides at once there.
                    .clipShape(RevealShape(fraction: out ? 1 : min(1, rail.width / width), onRight: onRight))
                    .animation(out ? RailHover.reveal : RailHover.conceal, value: out)
                    .opacity(out ? 1 : 0)
                    .animation(out ? nil : .linear(duration: 0.01).delay(0.22), value: out)
                    .allowsHitTesting(out)
                    .offset(x: onRight ? rail.maxX - width : rail.minX, y: rail.minY)
            }
        }
    }
}

/// Expand's reveal: the sidebar shown from the rail's edge out to `fraction` of its width, with its rounded corners.
private struct RevealShape: Shape {
    var fraction: CGFloat
    let onRight: Bool
    var animatableData: CGFloat {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        // Fully out, nothing is clipped, so the card's shadow shows.
        guard fraction < 0.999 else { return Path(rect.insetBy(dx: -40, dy: -40)) }
        let width = rect.width * max(0, fraction)
        let shown = CGRect(x: onRight ? rect.maxX - width : rect.minX, y: rect.minY, width: width, height: rect.height)
        return Path(roundedRect: shown, cornerRadius: Radius.card + 4, style: .continuous)
    }
}
