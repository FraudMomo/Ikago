import AppKit
import SwiftUI

/// What the icon sidebar's hover effects draw over the page (`RailHover`), in their own window over the browser window
/// (`RailOverlay`, the same size, so window coordinates match after flipping). Everything here is placed from
/// `RailHoverModel`'s state, never measured on the fly.
struct RailHoverLayers: View {
    let state: BrowserState
    let chrome: ChromeModel
    let palette: CommandPaletteModel
    weak var commands: BrowserCommands?

    var body: some View {
        GeometryReader { geometry in
            switch state.browserPreferences.railHover {
            case .expand: RailExpandPanel(state: state, chrome: chrome, palette: palette, size: geometry.size, commands: commands)
            case .magnify: RailMagnifyLayer(state: state, chrome: chrome, size: geometry.size, commands: commands)
            case nil: EmptyView()
            }
        }
        .environment(\.colorScheme, state.isDark ? .dark : .light)
    }
}

/// Window coordinates (from the bottom) to the overlay's (from the top).
private func flipped(_ rect: CGRect, in size: CGSize) -> CGRect {
    CGRect(x: rect.minX, y: size.height - rect.maxY, width: rect.width, height: rect.height)
}

// MARK: - Expand

/// Expand: the full sidebar (`SidebarView`) opens over the rail and the page while the pointer is on it, laid out as
/// when it is always shown: the same top row, address field, essentials, groups and bottom bar, and the same drags
/// (reorder, into groups, out to split the page). It sits on the rail's frame from when it opened (`anchor`) and is the
/// sidebar's own width when out (`RailHoverModel.expandWidth`); its edge grows from the rail's while it fades in. The
/// window's traffic lights move into its top row meanwhile (`positionTrafficLights`) and stay uncovered: the panel has
/// a hole where they are, and the pointer goes through it to them.
private struct RailExpandPanel: View {
    let state: BrowserState
    let chrome: ChromeModel
    let palette: CommandPaletteModel
    let size: CGSize
    weak var commands: BrowserCommands?

    var body: some View {
        let model = chrome.rail
        let out = model.expanded
        // Read where the lights are again each time they move (`lightsMoves`): they leave the rail's column for the
        // sidebar's top row while it is out.
        let lights = model.shown && model.lightsMoves >= 0 ? model.lightFrames() : []
        if let anchor = model.anchor {
            let rail = flipped(anchor, in: size)
            let full = model.expandWidth()
            let onRight = state.sidebarOnRight
            let alignment: Alignment = onRight ? .trailing : .leading
            let edge = out ? full : min(full, rail.width)
            ZStack(alignment: alignment) {
                RailExpandBackdrop(state: state, raised: out)
                    .frame(width: edge, height: rail.height)
                SidebarView(state: state, chrome: chrome, palette: palette, commands: commands)
                    .environment(\.sidebarOverRail, true)
                    .frame(width: full, height: rail.height)
                    .opacity(out ? 1 : 0)
                    .mask(alignment: alignment) { Rectangle().frame(width: edge) }
            }
            .animation(out ? RailHover.reveal : RailHover.conceal, value: out)
            .frame(width: full, height: rail.height, alignment: alignment)
            .opacity(model.shown ? 1 : 0)
            .animation(nil, value: model.shown)
            .allowsHitTesting(out)
            .position(x: onRight ? rail.maxX - full / 2 : rail.minX + full / 2, y: rail.midY)
            .frame(width: size.width, height: size.height)
            .mask { LightsHole(lights: lights.map { flipped($0, in: size) }).animation(out ? RailHover.reveal : RailHover.conceal, value: lights) }
        }
    }
}

/// Everything, less a round hole over each of the window's traffic lights, so only the lights show through, never what
/// lies around them in the window below. The holes move with the lights as they glide between the rail's column and the
/// sidebar's row (on the same curve, set by the caller).
private struct LightsHole: View {
    let lights: [CGRect]
    var body: some View {
        Rectangle().overlay {
            ForEach(Array(lights.enumerated()), id: \.offset) { _, light in
                Circle()
                    .frame(width: light.width + 0.5, height: light.height + 0.5)
                    .position(x: light.midX, y: light.midY)
                    .blendMode(.destinationOut)
            }
        }
        .compositingGroup()
    }
}

/// Expand's backdrop: what the rail sits on, carried out over the page. The window's frost when the window is
/// frosted, else the window's color; with Liquid Glass and a rail that is its own card, that card's glass over the
/// color (glass alone would show the page through). A hairline rim and a shadow while it is out.
private struct RailExpandBackdrop: View {
    let state: BrowserState
    let raised: Bool

    var body: some View {
        let colors = state.palette
        let joined = state.sidebarJoinsWindow
        let shape = RoundedRectangle(cornerRadius: joined ? Radius.card : Radius.card + 4, style: .continuous)
        ZStack {
            if state.frostedChrome {
                SidebarVisualEffect(tint: colors.nsTint).overlay(colors.tint.opacity(WindowBackgroundView.frostTint))
            } else {
                colors.tint
                if !joined { Color.clear.surface(shape, colors) }
            }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(colors.separator.opacity(raised ? 1 : 0), lineWidth: 0.5))
        .background(CardShadow(shape: shape, color: .black.opacity(raised ? (colors.isDark ? 0.4 : 0.16) : 0), radius: 14, x: 2))
    }
}

// MARK: - Magnify

/// Magnify: a copy of the rail's items over the rail (whose own items step aside, `covered`), with the icons near the
/// pointer growing, and beneath them a row under the tile at the pointer that reaches out over the page with its name.
/// The row is only a backdrop and a name: the icon on it is the copy's own, so there is one icon per tab and the row and
/// the icons move together in one window. The row glides from tile to tile; a click on its name works like the tile.
private struct RailMagnifyLayer: View {
    let state: BrowserState
    let chrome: ChromeModel
    let size: CGSize
    weak var commands: BrowserCommands?

    var body: some View {
        let model = chrome.rail
        if let anchor = model.anchor {
            let rail = flipped(anchor, in: size)
            ZStack(alignment: .topLeading) {
                RailMagnifyRow(state: state, model: model, size: size, commands: commands)
                SidebarRail(state: state, chrome: chrome, commands: commands, magnified: true)
                    .frame(width: rail.width, height: rail.height)
                    .position(x: rail.midX, y: rail.midY)
            }
            .frame(width: size.width, height: size.height)
            .opacity(model.shown ? 1 : 0)
            .animation(nil, value: model.shown)
            .allowsHitTesting(model.shown)
        }
    }
}

/// The carousel's rows, like the Dock's icons: each stays on its own tile and only changes size. Under the pointer's tile
/// a full row with its name; under the tiles just above and below it shorter, quieter rows. Moving to the next tile the
/// rows reach out and draw back on one spring, a row that stops being a neighbour fades and a new one fades in; nothing
/// slides, so rows and icons never part. All of them fade and grow in with Magnify itself (`strength`) and back out.
private struct RailMagnifyRow: View {
    let state: BrowserState
    let model: RailHoverModel
    let size: CGSize
    weak var commands: BrowserCommands?

    var body: some View {
        let onRight = state.sidebarOnRight
        // Room for the longest row; each row is as wide as it shows.
        let box: CGFloat = 300
        if let center = model.hovered {
            let rows = model.neighbours.map { ($0, false) } + [(center, true)]
            let rail = flipped(center.tile, in: size)
            ZStack {
                ForEach(rows, id: \.0.key) { item, main in
                    let tile = flipped(item.tile, in: size)
                    RailRowContent(state: state, item: item, main: main, onRight: onRight, commands: commands) { width in
                        if main, abs(model.rowWidth - width) > 0.5 { model.rowWidth = width }
                    }
                    .frame(width: box, height: tile.height, alignment: onRight ? .trailing : .leading)
                    .position(x: onRight ? tile.maxX - box / 2 : tile.minX + box / 2, y: tile.midY)
                    .zIndex(main ? 1 : 0)
                    .transition(.opacity)
                }
            }
            .frame(width: size.width, height: size.height)
            .scaleEffect(0.94 + 0.06 * model.strength, anchor: UnitPoint(x: (onRight ? rail.maxX : rail.minX) / max(size.width, 1),
                                                                            y: rail.midY / max(size.height, 1)))
            .opacity(model.strength)
            .allowsHitTesting(model.shown)
        }
    }
}

/// One row: room for the tile's icon (drawn by the rail's copy above it) and the item's name, on the floating surface;
/// the hovered tab's row also has its controls (sound, close).
/// It is laid out at its full length always and shown to `width`, which the spring animates: the hovered row shows all
/// of it, a neighbour at most `neighbourWidth`, its name fading where it is cut.
private struct RailRowContent: View {
    let state: BrowserState
    let item: RailHoveredItem
    let main: Bool
    let onRight: Bool
    weak var commands: BrowserCommands?
    /// Reports the width the row shows.
    let shows: (CGFloat) -> Void
    @State private var natural: CGFloat = 0

    static let neighbourWidth: CGFloat = 132

    var body: some View {
        let colors = state.palette
        let shape = RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
        let width = natural == 0 ? nil : main ? natural : min(natural, Self.neighbourWidth)
        let cut = !main && natural > Self.neighbourWidth
        let tab = main ? tabItem : nil
        HStack(spacing: 4) {
            if onRight, let tab { controls(tab, colors) }
            Button(action: activate) {
                HStack(spacing: 4) {
                    if onRight { title(colors) }
                    Color.clear.frame(width: 36, height: 36)
                    if !onRight { title(colors) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if !onRight, let tab { controls(tab, colors) }
        }
        .padding(onRight ? .leading : .trailing, tab == nil ? 12 : 7)
        .fixedSize()
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { natural = $0 }
        .frame(width: width, alignment: onRight ? .trailing : .leading)
        .mask(alignment: onRight ? .trailing : .leading) {
            // The name fades out where a neighbour's row cuts it.
            LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: cut ? 0.8 : 1),
                                   .init(color: .black.opacity(cut ? 0 : 1), location: 1)],
                           startPoint: onRight ? .trailing : .leading, endPoint: onRight ? .leading : .trailing)
        }
        .frame(height: main ? 36 : 30)
        .background { if active { shape.fill(colors.selected) } }
        .contentShape(shape)
        .surface(shape, colors, tintOpacity: 0.85)
        .background(CardShadow(shape: shape, color: .black.opacity((colors.isDark ? 0.3 : 0.12) * (main ? 1 : 0.6)), radius: main ? 10 : 6, x: 0, y: 2))
        // The rows beside it step back, so the one under the pointer stands out.
        .opacity(main ? 1 : 0.6)
        .contextMenu { menu }
        .onChange(of: width, initial: true) { _, now in shows(now ?? 0) }
    }

    /// The hovered tab's controls, as on the full sidebar's rows: camera, microphone and sound while in use, and close.
    private func controls(_ tab: TabItem, _ colors: Palette) -> some View {
        HStack(spacing: 4) {
            TabMediaIndicators(tab: tab, colors: colors, commands: commands)
            RailTabCloseButton(tab: tab, colors: colors, commands: commands)
        }
    }

    private var tabItem: TabItem? {
        if case .tab(let id) = item.key.kind { return state.tab(id) }
        return nil
    }

    private func title(_ colors: Palette) -> some View {
        HStack(spacing: 6) {
            Text(name).font(.system(size: 13, weight: main ? .semibold : .regular)).foregroundStyle(main ? colors.text : colors.secondary).lineLimit(1)
            if let detail { Text(detail).font(.system(size: 11)).foregroundStyle(colors.secondary).lineLimit(1) }
        }
        .frame(maxWidth: 220, alignment: onRight ? .trailing : .leading)
    }

    private var active: Bool {
        if case .tab(let id) = item.key.kind { return id == state.activeTabID }
        return false
    }

    private var name: String {
        switch item.key.kind {
        case .tab(let id): state.tab(id)?.displayTitle ?? ""
        case .folder(let id): state.folders.first { $0.id == id }?.name ?? ""
        case .newTab: "New Tab"
        }
    }

    private var detail: String? {
        guard case .folder(let id) = item.key.kind, let folder = state.folders.first(where: { $0.id == id }) else { return nil }
        if folder.isClosed == true { return "Hidden" }
        let count = state.tabs(inSubtree: folder).count
        return "\(count)"
    }

    private func activate() {
        switch item.key.kind {
        case .tab(let id):
            if NSEvent.modifierFlags.contains(.option) { commands?.peekTab(id) } else { state.select(id) }
        case .folder(let id):
            if state.folders.first(where: { $0.id == id })?.isClosed == true { state.reopenFolder(id) } else { state.toggleFolder(id) }
        case .newTab:
            commands?.newTab()
        }
    }

    @ViewBuilder private var menu: some View {
        switch item.key.kind {
        case .tab(let id):
            if let tab = state.tab(id) { TabContextMenu(tab: tab, state: state, commands: commands) }
        case .folder(let id):
            if let folder = state.folders.first(where: { $0.id == id }) { FolderContextMenu(folder: folder, state: state, commands: commands) }
        case .newTab:
            EmptyView()
        }
    }
}
