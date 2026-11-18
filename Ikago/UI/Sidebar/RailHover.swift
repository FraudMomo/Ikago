import AppKit
import SwiftUI

/// The icon sidebar's hover effects (Settings ▸ Appearance ▸ Layout ▸ Window and Sidebar ▸ Icon sidebar on hover).
///
/// - Magnify, like the Dock but sideways: the rows near the pointer reach out past the rail as pills showing their name,
///   the row under the pointer furthest and its neighbours less (`RailMagnifyLayer`). Rows never change height or place,
///   so nothing the pointer measures moves under it: the effect can't feed back into itself, and moving up and down only
///   lengthens and shortens pills. A closed group under the pointer opens an island: its name, and a card beside the
///   rail with its tabs and the groups inside it as a tree, which stays while the pointer is on it (`RailIsland`).
/// - Expand: the full sidebar slides out over the rail and the page (`RailExpandPanel`), and slides back when the pointer
///   leaves it. The page never moves or resizes for either.
///
/// Off by default, and off under Reduce Motion.
enum RailHover {
    /// Expand's width: room for each row's name beside its icon.
    static let expandedWidth: CGFloat = 240
    /// How far from the pointer rows still reach out, in points: about two tiles either way.
    static let reach: CGFloat = 80
    /// The longest a name runs past its icon.
    static let longestName: CGFloat = 240
    /// The names' font in the pills (kept in AppKit too, to measure them).
    static let nameSize: CGFloat = 12.5
    @MainActor static let nameFont = NSFont.systemFont(ofSize: nameSize, weight: .medium)
    /// Pills follow the pointer on a spring each move retargets, so they track it closely without overshooting.
    static let follow = Animation.interactiveSpring(response: 0.2, dampingFraction: 0.9)
    static let reveal = Animation.spring(response: 0.3, dampingFraction: 0.86)
    static let conceal = Animation.spring(response: 0.24, dampingFraction: 1)
    /// How long the pointer rests on the rail before the sidebar expands, so crossing it to reach the window's edge
    /// doesn't flash the sidebar open.
    static let expandDelay: Duration = .milliseconds(70)
    /// How long Expand's sidebar or an island stays after the pointer leaves it, to forgive a slip over the edge.
    static let leaveGrace: Duration = .milliseconds(200)

    /// 1 at the pointer, easing to 0 at `reach`: a raised cosine (pills grow and shrink without a kink), sharpened so
    /// the row under the pointer clearly leads and its neighbours, a tile away, reach out only about a third as far.
    static func closeness(_ distance: CGFloat) -> CGFloat {
        guard abs(distance) < reach else { return 0 }
        return pow((cos(.pi * distance / reach) + 1) / 2, 1.6)
    }

    /// How far the row under the pointer reaches past its icon at least, so every row follows one profile whatever its
    /// name: the row under the pointer always reaches furthest.
    static let profile: CGFloat = 170

    /// How far past its icon a row reaches with the pointer `distance` points away: under the pointer the profile, or its
    /// whole name when longer (up to `longestName`); less with distance, nothing from `reach` on.
    static func reachOut(nameWidth: CGFloat, distance: CGFloat) -> CGFloat {
        max(profile, min(nameWidth + 24, longestName + 24)) * closeness(distance)
    }

    @MainActor static func nameWidth(_ name: String) -> CGFloat {
        ceil((name as NSString).size(withAttributes: [.font: nameFont]).width)
    }
}

/// One host's coordinate space in the rail: the rail itself, and its list, which scrolls in its own `NSHostingView`.
/// Tiles measure their frames in it with SwiftUI's layout (stable: scrolling doesn't change them) and the space's
/// anchor view turns those into window coordinates live, scroll included, so the rail and its list agree with the
/// pointer exactly.
@MainActor
final class RailSpace {
    let name: String
    weak var view: NSView?
    init(_ name: String) { self.name = name }

    /// `local` in window coordinates (AppKit's, from the bottom), or nil when the tile is scrolled out of sight.
    func windowRect(_ local: CGRect) -> CGRect? {
        guard let view, view.window != nil, view.visibleRect.contains(CGPoint(x: local.midX, y: local.midY)) else { return nil }
        return view.convert(local, to: nil)
    }
}

/// Per window: where the pointer is over the rail, the rail's tiles, and which effect is showing.
@MainActor @Observable
final class RailHoverModel {
    enum Tile: Hashable {
        case tab(String)
        case folder(String)
    }

    struct Placement {
        var frame: CGRect
        let space: RailSpace
    }

    /// The pointer over the rail, in window coordinates; nil elsewhere.
    private(set) var pointer: NSPoint?
    /// Bumped when the rail's list scrolls under a still pointer: the tiles moved, so the pills follow.
    private(set) var scrolled = 0
    private(set) var tiles: [Tile: Placement] = [:]
    /// Magnify: the group whose island is open.
    private(set) var island: String? { didSet { if island == nil, oldValue != nil { onRelease?() } } }
    /// Expand: the full sidebar is out.
    private(set) var expanded = false { didSet { if !expanded, oldValue { onRelease?() } } }
    /// The rail's own space, for its frame in the window (Expand's sidebar covers it exactly).
    @ObservationIgnored weak var rail: RailSpace?
    /// The rail's list and the wider rail's, kept scrolled alike as the rail widens and narrows.
    @ObservationIgnored weak var list: RailSpace?
    @ObservationIgnored weak var expandedList: RailSpace?

    @ObservationIgnored private var islandHovered = false
    /// Called when the effects stop holding the sidebar out (an island closed, the wider rail went back, the pointer left
    /// the leading card), so a rail that slid in from the window's edge can slide away again.
    @ObservationIgnored var onRelease: (() -> Void)?
    /// Something the effects show is in use: a rail that slid in from the window's edge stays while it is.
    var holdsSidebar: Bool { island != nil || expanded || onPill }
    /// Magnify: the pointer is on the rail, or on the leading row's card where it reaches out over the page. The card
    /// bridges the rail and the page: on it, the rows hold still (the pointer keeps its last place on the rail).
    @ObservationIgnored private var onRail = false
    @ObservationIgnored private var onPill = false
    @ObservationIgnored private var pointerTask: Task<Void, Never>?
    @ObservationIgnored private var panelHovered = false
    @ObservationIgnored private var islandTask: Task<Void, Never>?
    @ObservationIgnored private var expandTask: Task<Void, Never>?
    @ObservationIgnored private var effect: RailHoverEffect?
    #if DEBUG
    /// Checks hold the pointer still so a real one passing over the window doesn't move it.
    @ObservationIgnored var heldByCheck = false
    #endif

    // MARK: Tiles

    func place(_ tile: Tile, frame: CGRect, in space: RailSpace) {
        if let old = tiles[tile], old.frame == frame, old.space === space { return }
        tiles[tile] = Placement(frame: frame, space: space)
    }

    /// Only the space that placed it removes it: a tile moving between the rail and its list appears in the new one
    /// before it leaves the old.
    func remove(_ tile: Tile, from space: RailSpace) {
        if tiles[tile]?.space === space { tiles[tile] = nil }
    }

    /// The rail's frame in window coordinates (AppKit's), from its anchor view, which is right in any host: docked, or
    /// slid in from the edge in its own.
    var railWindowRect: CGRect? {
        guard let view = rail?.view, view.window != nil else { return nil }
        return view.convert(view.bounds, to: nil)
    }

    /// The rail's frame in a layer whose global origin is `origin` (SwiftUI's space, from the window's top).
    func railRect(from origin: CGPoint) -> CGRect? {
        guard let rect = railWindowRect, let height = rail?.view?.window?.contentView?.bounds.height else { return nil }
        return CGRect(x: rect.minX - origin.x, y: height - rect.maxY - origin.y, width: rect.width, height: rect.height)
    }

    func windowRect(_ tile: Tile) -> CGRect? {
        tiles[tile].flatMap { $0.space.windowRect($0.frame) }
    }

    func listScrolled() {
        if pointer != nil { scrolled &+= 1 }
    }

    // MARK: Pointer

    /// The rail's tracking view reports every move, entering and leaving (nil).
    func pointerMoved(_ point: NSPoint?, effect: RailHoverEffect?) {
        #if DEBUG
        if heldByCheck { return }
        #endif
        move(point, effect: effect)
    }

    func move(_ point: NSPoint?, effect: RailHoverEffect?) {
        if self.effect != effect { reset() }
        self.effect = effect
        switch effect {
        case .magnify:
            onRail = point != nil
            if let point {
                pointerTask?.cancel()
                if pointer != point { pointer = point }
            } else if !onPill {
                releasePointerSoon()
            }
            keepIsland(point)
        case .expand:
            pointer = nil
            if point != nil { expandSoon() } else { collapseSoon() }
        case nil:
            if pointer != nil { pointer = nil }
        }
    }

    /// Everything back at rest (the effect changed, or the rail went away).
    func reset() {
        islandTask?.cancel(); expandTask?.cancel(); pointerTask?.cancel()
        onRail = false
        onPill = false
        pointer = nil
        island = nil
        islandHovered = false
        panelHovered = false
        if expanded { expanded = false }
    }

    /// The leading row's card reports the pointer on it (its own AppKit tracking view).
    func pillHover(_ inside: Bool) {
        onPill = inside
        if inside { pointerTask?.cancel() } else {
            if !onRail { releasePointerSoon() }
            onRelease?()
        }
    }

    /// Off the rail and off the card, the rows go back after a moment, enough to cross from one to the other.
    private func releasePointerSoon() {
        pointerTask?.cancel()
        pointerTask = Task { [weak self] in
            try? await Task.sleep(for: RailHover.leaveGrace)
            guard !Task.isCancelled, let self, !self.onRail, !self.onPill else { return }
            self.pointer = nil
        }
    }

    // MARK: Islands

    /// A click on a shut group's tile opens its island (and a second click closes it).
    func toggleIsland(_ id: String) {
        guard island != id else { closeIsland(); return }
        islandTask?.cancel()
        // The pointer is on the tile, which the island's name now covers.
        islandHovered = true
        withAnimation(RailHover.reveal) { island = id }
    }

    /// An open island closes shortly after the pointer leaves both it and its group's tile.
    private func keepIsland(_ point: NSPoint?) {
        guard let island else { return }
        let onTile = point.map { windowRect(.folder(island))?.contains($0) == true } ?? false
        if onTile || islandHovered { islandTask?.cancel() } else { closeIslandSoon() }
    }

    func islandHover(_ inside: Bool) {
        islandHovered = inside
        if inside { islandTask?.cancel() } else { closeIslandSoon() }
    }

    func closeIsland() {
        islandTask?.cancel()
        islandHovered = false
        withAnimation(RailHover.conceal) { island = nil }
    }

    private func closeIslandSoon() {
        schedule(after: RailHover.leaveGrace) { model in
            guard !model.islandHovered else { return }
            withAnimation(RailHover.conceal) { model.island = nil }
        }
    }

    private func schedule(after delay: Duration, _ body: @escaping @MainActor (RailHoverModel) -> Void) {
        islandTask?.cancel()
        islandTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            body(self)
        }
    }

    // MARK: Expand

    private func expandSoon() {
        guard !expanded else { expandTask?.cancel(); return }
        guard expandTask == nil else { return }
        expandTask = Task { [weak self] in
            try? await Task.sleep(for: RailHover.expandDelay)
            guard !Task.isCancelled, let self else { return }
            self.expandTask = nil
            // The panel animates itself (`RailExpandPanel`): the clip on one curve, the fade on another.
            Self.scroll(self.expandedList, like: self.list)
            self.expanded = true
        }
    }

    private func collapseSoon(holds: @escaping @MainActor () -> Bool = { false }) {
        expandTask?.cancel()
        expandTask = nil
        guard expanded else { return }
        expandTask = Task { [weak self] in
            try? await Task.sleep(for: RailHover.leaveGrace)
            guard !Task.isCancelled, let self else { return }
            self.expandTask = nil
            guard !self.panelHovered, !holds() else { return }
            self.expanded = false
            Self.scroll(self.list, like: self.expandedList)
        }
    }

    /// The expanded sidebar keeps itself out while the pointer is on it, or while something in it is in use (an address
    /// being typed, a drag, the downloads list).
    func panelHover(_ inside: Bool, holds: @escaping @MainActor () -> Bool) {
        panelHovered = inside
        if inside { expandTask?.cancel(); expandTask = nil } else { collapseSoon(holds: holds) }
    }

    /// Scrolls one rail list to where the other is, so the wider rail shows the same rows the rail did.
    private static func scroll(_ target: RailSpace?, like source: RailSpace?) {
        guard let from = source?.view?.enclosingScrollView, let to = target?.view?.enclosingScrollView else { return }
        to.contentView.scroll(to: from.contentView.bounds.origin)
        to.reflectScrolledClipView(to.contentView)
    }

    func collapse() {
        expandTask?.cancel(); expandTask = nil
        panelHovered = false
        if expanded { expanded = false }
    }
}

extension BrowserState {
    /// Magnify opens an island, on a click, for any group the rail shows (a hidden one comes back with a click). Its
    /// groups always stay shut in the rail: their tabs show only in the island.
    func railIslandOpens(_ folderID: String) -> Bool {
        folders.first { $0.id == folderID }.map { $0.isClosed != true } ?? false
    }
}

// MARK: - Environment

private struct RailHoverModelKey: EnvironmentKey { static let defaultValue: RailHoverModel? = nil }
private struct RailSpaceKey: EnvironmentKey { static let defaultValue: RailSpace? = nil }

extension EnvironmentValues {
    /// Set while Magnify is on: the rail's tiles report where they are.
    var railHover: RailHoverModel? {
        get { self[RailHoverModelKey.self] }
        set { self[RailHoverModelKey.self] = newValue }
    }
    var railSpace: RailSpace? {
        get { self[RailSpaceKey.self] }
        set { self[RailSpaceKey.self] = newValue }
    }
}

extension View {
    /// A rail tile Magnify reaches out from: its frame in its host's space, kept current in the window's model.
    func railTile(_ tile: RailHoverModel.Tile) -> some View { modifier(RailTileReport(tile: tile)) }

    /// Makes this view a rail coordinate space: tiles inside measure themselves against it.
    func railSpace(_ space: RailSpace, onScroll: (() -> Void)? = nil) -> some View {
        coordinateSpace(.named(space.name))
            .background(RailSpaceAnchor(space: space, onScroll: onScroll))
            .environment(\.railSpace, space)
    }
}

private struct RailTileReport: ViewModifier {
    let tile: RailHoverModel.Tile
    @Environment(\.railHover) private var model
    @Environment(\.railSpace) private var space

    func body(content: Content) -> some View {
        if let model, let space {
            content
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(space.name)) } action: { model.place(tile, frame: $0, in: space) }
                .onDisappear { model.remove(tile, from: space) }
        } else {
            content
        }
    }
}

/// The view a `RailSpace` converts through. It fills the space's view exactly, flipped like SwiftUI, and reports when
/// the list scrolls (the clip view's bounds move, the tiles' own frames don't).
private struct RailSpaceAnchor: NSViewRepresentable {
    let space: RailSpace
    let onScroll: (() -> Void)?

    func makeNSView(context: Context) -> AnchorView { AnchorView() }
    func updateNSView(_ view: AnchorView, context: Context) {
        space.view = view
        view.onScroll = onScroll
    }

    final class AnchorView: NSView {
        var onScroll: (() -> Void)?
        private var observer: NSObjectProtocol?
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observer.map(NotificationCenter.default.removeObserver)
            observer = nil
            guard window != nil, let clip = enclosingScrollView?.contentView else { return }
            clip.postsBoundsChangedNotifications = true
            observer = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.onScroll?() }
            }
        }
    }
}

// MARK: - Tracking

/// Follows the pointer over the whole rail, its list included (which has its own host, so SwiftUI's hover there doesn't
/// reach the rail), in window coordinates.
struct RailPointerTracker: FillingViewRepresentable {
    let onMove: (NSPoint?) -> Void
    func makeNSView(context: Context) -> RailTrackingView { RailTrackingView() }
    func updateNSView(_ view: RailTrackingView, context: Context) { view.onMove = onMove }
}

final class RailTrackingView: NSView {
    var onMove: (NSPoint?) -> Void = { _ in }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { onMove(event.locationInWindow) }
    override func mouseMoved(with event: NSEvent) { onMove(event.locationInWindow) }
    override func mouseExited(with event: NSEvent) { onMove(nil) }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { onMove(nil) }
    }
}
