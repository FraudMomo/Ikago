import AppKit
import SwiftUI

/// Per window: the icon sidebar's hover effects (`RailHover`) as one small state machine.
///
/// ```text
///            pointer on a still rail            delay passed, rail still
///   idle ─────────────────────────────▶ arming ─────────────────────────▶ open ◀──────┐
///    ▲                                    │ pointer off the rail          │ pointer   │ pointer back
///    │◀───────────────────────────────────┘                               │ left      │ in its zone
///    │                                                                    ▼           │
///    │          settled                    grace passed                leaving ───────┘
///    └──────────────────── closing ◀──────────────────────────────────────┘
///                             │ pointer back on the rail ──▶ open
///
///   any state ──▶ idle at once: the effect changed, the rail went away or moved, the window closed.
/// ```
///
/// While the machine is anywhere but `idle` a timer reads the real pointer every frame (`tick`) and takes at most one
/// step; nothing else changes the phase. Leaving never depends on an "exited" event, which AppKit doesn't send when a
/// window covers the rail, the rail slides away under a still pointer, or the style changes: the timer sees the pointer
/// outside and the grace runs out. Everything the views draw is derived from the phase.
@MainActor @Observable
final class RailHoverModel {
    enum Phase: Equatable {
        case idle
        /// The pointer is on the rail; the effect opens once it has rested `delay` and the rail has stopped moving.
        case arming(since: ContinuousClock.Instant)
        case open
        /// The pointer is outside the effect; it closes after `leaveGrace` unless the pointer comes back.
        case leaving(since: ContinuousClock.Instant)
        /// Animating back to the rail; the overlay goes once it has settled.
        case closing(since: ContinuousClock.Instant)
    }

    private(set) var phase: Phase = .idle {
        didSet {
            guard phase != oldValue else { return }
            entered(phase, from: oldValue)
        }
    }
    /// The effect this run of the machine is for.
    private(set) var effect: RailHoverEffect?
    /// The rail the pointer came onto: the effects follow only it.
    private(set) var surface: RailSurface?
    /// The rail's frame (window coordinates) when the effect opened; while shown the rail must stay there.
    private(set) var anchor: CGRect?
    /// Magnify: the pointer on the rail (window coordinates), for the icons' growth.
    private(set) var pointer: NSPoint?
    /// Magnify: 0 at rest, 1 grown, animated.
    private(set) var strength: CGFloat = 0
    /// Magnify: the item under the pointer, grown most with its row over the page.
    private(set) var hovered: RailHoveredItem?
    /// Magnify: the items just above and below it, grown a little with smaller rows.
    private(set) var neighbours: [RailHoveredItem] = []
    /// The overlay window is on screen (set by its owner). The rail's own items step aside only then, so Expand's sidebar
    /// that failed to show can never leave the rail blank.
    var overlayOnScreen = false

    /// Something is drawn in the overlay: open, leaving or closing.
    var shown: Bool {
        switch phase {
        case .open, .leaving, .closing: true
        case .idle, .arming: false
        }
    }
    /// Expand: Expand's sidebar is out (it narrows back while closing).
    var expanded: Bool {
        guard effect == .expand else { return false }
        switch phase {
        case .open, .leaving: return true
        default: return false
        }
    }
    /// A copy of the rail lies over it in the overlay (Expand's sidebar, or Magnify's), so the rail's own items step aside.
    var covered: Bool { shown && overlayOnScreen }
    /// Magnify: the tab row is on screen.
    var rowOnScreen: Bool { effect == .magnify && covered && hovered != nil }
    /// A rail slid in from the window's edge stays while the effects run.
    var holdsSidebar: Bool { phase != .idle }

    // MARK: Wiring

    /// The overlay window shows (true) or goes (false).
    @ObservationIgnored var onOverlay: ((Bool) -> Void)?
    /// The overlay window should be in place, invisible, before it shows (from `arming`): one ordered in as it shows
    /// lost its first frames, and the icons popped instead of growing.
    @ObservationIgnored var onPrepare: (() -> Void)?
    /// The overlay window lets the pointer through (true) or takes it where it draws (false). It lets it through
    /// while nothing shows and over the window's traffic lights: a click on the hole above them still went to the
    /// overlay, not to them.
    @ObservationIgnored var onPassThrough: ((Bool) -> Void)?
    @ObservationIgnored private(set) var passingThrough: Bool?
    /// The machine is back at `idle`: a rail slid in from the edge may slide away.
    @ObservationIgnored var onRelease: (() -> Void)?
    /// Something else in the window is in use (an address being typed, a drag, the downloads list): don't close.
    @ObservationIgnored var holdsChrome: () -> Bool = { false }
    /// A tab or group is being dragged. Outside the effect's own zone the overlay lets the drag through to the browser
    /// window, so drops on the page (split view) and elsewhere reach their targets: the overlay window covers the whole
    /// browser window and its host is a drop destination wherever it is.
    @ObservationIgnored var isDragging: () -> Bool = { false }
    /// The window's own traffic lights (window coordinates) when it draws them; Expand's sidebar leaves them uncovered.
    @ObservationIgnored var lightsRect: () -> CGRect? = { nil }
    /// Each drawn traffic light where it is headed (window coordinates), for the round holes over them.
    @ObservationIgnored var lightFrames: () -> [CGRect] = { [] }
    /// Bumped whenever the traffic lights move (into Expand's top row and back), so the hole over them follows.
    var lightsMoves = 0
    /// Expand's width when out: the full sidebar's.
    @ObservationIgnored var expandWidth: () -> CGFloat = { RailHover.expandedWidth }
    /// The list of the rail's copy in the overlay, kept scrolled like the rail's (`listScrolled`).
    @ObservationIgnored weak var overlayList: RailSpace?
    @ObservationIgnored private var mirroring = false
    /// Magnify: the hovered row's measured width, for where the pointer may be and to keep the rows beside it shorter.
    var rowWidth: CGFloat = 0
    #if DEBUG
    /// Checks drive the machine with a pretend pointer (window coordinates; nil is off the window).
    @ObservationIgnored var pretendPointer: NSPoint??
    #endif

    /// The rail's own buttons (the sidebar button, the foot's controls), in the window's SwiftUI coordinates (from the
    /// top), by who reported them. The overlay always lets the pointer through over them, in every effect: a click there
    /// is for the button, and the overlay window (which the window server routes the pointer to) swallowed it.
    @ObservationIgnored private var buttons: [String: CGRect] = [:]
    func reportButton(_ key: String, frame: CGRect?) { buttons[key] = frame }

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastRail: CGRect?
    /// Each item's frame, by the views that drew it (one at a time, but a rebuilt one registers before the last goes).
    @ObservationIgnored private var items: [RailItemKey: [UUID: RailItemEntry]] = [:]

    // MARK: Inputs

    /// A rail's tracking view saw the pointer on it. Starts the machine; on Magnify the icons follow at once.
    func pointerMoved(_ point: NSPoint, rail: RailSurface, effect: RailHoverEffect?) {
        #if DEBUG
        if pretendPointer != nil { return }
        #endif
        guard let effect else { reset(); return }
        if self.effect != effect || surface !== rail {
            reset()
            self.effect = effect
            surface = rail
        }
        start()
        if effect == .magnify, shown { follow(point) }
    }

    /// Back to `idle` at once, nothing shown.
    func reset() {
        phase = .idle
        effect = nil
    }

    /// A rail came on screen. Style switches mount the next rail before the last one goes, so the newest is the one to
    /// follow (unless the effects are in use on another).
    func appeared(_ rail: RailSurface) {
        if surface == nil || phase == .idle { surface = rail }
        // Put the overlay window in place ahead of the first hover, once the window is up.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.onPrepare?() }
    }

    func disappeared(_ rail: RailSurface) {
        items = items.filter { $0.key.surface != rail.id }
        guard surface === rail else { return }
        reset()
        surface = nil
    }

    /// The copy of the rail in the overlay mounted: its list starts where the rail's is.
    func adoptOverlayList(_ list: RailSpace) {
        overlayList = list
        DispatchQueue.main.async { [weak self] in Self.scroll(list, like: self?.surface?.list) }
    }

    /// A rail list scrolled: the other one (the rail's, or its copy's in the overlay) follows, so a scroll that lands on
    /// either keeps the icons under each other.
    func listScrolled(_ list: RailSpace) {
        guard !mirroring, shown else { return }
        mirroring = true
        defer { mirroring = false }
        if list === surface?.list { Self.scroll(overlayList, like: list) } else if list === overlayList { Self.scroll(surface?.list, like: list) }
    }

    #if DEBUG
    /// Starts the machine as a rail's tracking view would, for checks.
    func startForCheck(rail: RailSurface, effect: RailHoverEffect) {
        if self.effect != effect || surface !== rail { reset(); self.effect = effect; surface = rail }
        start()
        tick()
    }
    #endif

    // MARK: Items (Magnify)

    /// `owner` is the view registering: a tile rebuilt registers before the old one goes, and the old one's going must
    /// not take the new one's place with it.
    func register(_ key: RailItemKey, owner: UUID, space: RailSpace, frame: CGRect, iconSize: CGFloat) {
        items[key, default: [:]][owner] = RailItemEntry(space: space, frame: frame, iconSize: iconSize)
    }

    func unregister(_ key: RailItemKey, owner: UUID) {
        items[key]?[owner] = nil
        if items[key]?.isEmpty == true { items[key] = nil }
    }

    /// The items of the rail the effects follow that are on screen (not scrolled out of the list), top first, each as
    /// its 36 pt tile in window coordinates.
    private func visibleItems(rail: CGRect) -> [RailHoveredItem] {
        guard let surface else { return [] }
        var found: [RailHoveredItem] = []
        for (key, owners) in items where key.surface == surface.id {
            guard let entry = owners.values.first(where: { $0.space?.view?.window != nil }), let space = entry.space, let icon = space.windowRect(entry.frame) else { continue }
            if let scroll = space.view?.enclosingScrollView {
                let clip = scroll.convert(scroll.bounds, to: nil)
                guard icon.midY > clip.minY, icon.midY < clip.maxY else { continue }
            }
            let tile = CGRect(x: rail.minX + SidebarRail.tileInset, y: icon.midY - 18, width: 36, height: 36)
            found.append(RailHoveredItem(key: key, tile: tile, iconSize: entry.iconSize))
        }
        return found.sorted { $0.tile.midY > $1.tile.midY }
    }

    /// Magnify's carousel: the tile nearest the pointer (by height alone, so the pointer may be on its row over the
    /// page) and the tiles just above and below it. Sizes change only when that tile changes, never with the pointer
    /// moving within it.
    private func follow(_ point: NSPoint, rail: CGRect? = nil) {
        guard let rail = rail ?? surface?.windowRect else { return }
        if pointer != point { pointer = point }
        let list = visibleItems(rail: rail)
        guard let index = list.indices.min(by: { abs(list[$0].tile.midY - point.y) < abs(list[$1].tile.midY - point.y) }),
              abs(list[index].tile.midY - point.y) <= 24 else {
            if hovered != nil { hovered = nil; neighbours = [] }
            return
        }
        let item = list[index]
        let around = [index - 1, index + 1].filter(list.indices.contains).map { list[$0] }
        if item != hovered || around != neighbours {
            withAnimation(RailHover.glide) {
                hovered = item
                neighbours = around
            }
        }
    }

    /// An item's place in the carousel.
    func role(of key: RailItemKey) -> RailMagnifyRole? {
        if hovered?.key == key { return .hovered }
        if neighbours.contains(where: { $0.key == key }) { return .neighbour }
        return nil
    }

    // MARK: The machine

    private func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        lastRail = nil
    }

    /// One step: read the pointer and the rail, then move along at most one edge of the graph.
    func tick() {
        guard let effect, let surface, let window = surface.rail.view?.window, let rail = surface.windowRect else {
            reset(); stop(); return
        }
        let point = pointerLocation(in: window)
        let still = lastRail.map { Self.same($0, rail) } ?? false
        lastRail = rail
        // The rail moved or resized while the effect showed over it (slid away, the window resized): let go at once.
        if shown, let anchor, !Self.same(anchor, rail) { reset(); stop(); return }
        let onRail = point.map(rail.contains) ?? false
        // Expand opens only from the tiles: over the rail's own buttons (the sidebar button, Tab Groups, Spaces at the foot)
        // the full sidebar would cover them, and a click meant for them landed on it instead.
        // The rail's own buttons are never under the effects: over them they let go at once and let the click through.
        let overButtons = point.map { point in
            let height = window.contentView?.bounds.height ?? 0
            return buttons.values.contains { CGRect(x: $0.minX, y: height - $0.maxY, width: $0.width, height: $0.height).contains(point) }
        } ?? false
        let onTiles = !overButtons && (effect != .expand || (point.map { tilesRect(rail)?.contains($0) ?? false } ?? false))
        let onRight = rail.midX > window.frame.width / 2
        let inZone = !overButtons && (onRail || (point.map { zone(rail, onRight: onRight)?.contains($0) ?? false } ?? false))
        let dragging = isDragging()
        // Magnify steps aside for a drag: its rows and grown icons stayed over the tiles the row moves among, and the
        // rail's own icons stayed hidden under them.
        if effect == .magnify && dragging {
            if passingThrough != true { passingThrough = true; onPassThrough?(true) }
            if phase != .idle { phase = .idle }
            return
        }
        let overLights = point.map { lightsRect()?.insetBy(dx: -4, dy: -4).contains($0) ?? false } ?? false
        let through = !shown || overLights || overButtons || (dragging && !inZone)
        if through != passingThrough { passingThrough = through; onPassThrough?(through) }
        // The carousel holds still during a drag: its springs on every tile crossed made dragging stutter.
        if effect == .magnify, inZone, let point, shown, !dragging { follow(point, rail: rail) }
        let now = ContinuousClock.now

        switch phase {
        case .idle:
            if onRail && onTiles { phase = .arming(since: now) } else if !onRail { stop() }
        case .arming(let since):
            if !onRail || !onTiles { phase = .idle }
            else if still, now - since >= (effect == .expand ? RailHover.expandDelay : .zero) {
                anchor = rail
                phase = .open
                if effect == .magnify, let point { follow(point, rail: rail) }
            }
        case .open:
            if !inZone, !holdsChrome() { phase = .leaving(since: now) }
        case .leaving(let since):
            if inZone || holdsChrome() { phase = .open }
            else if now - since >= RailHover.leaveGrace { phase = .closing(since: now) }
        case .closing(let since):
            if onRail, onTiles, still { phase = .open }
            else if now - since >= RailHover.settle { phase = .idle }
        }
    }

    /// What each phase shows, set once on the way in.
    private func entered(_ new: Phase, from old: Phase) {
        let wasShown = Self.shows(old), isShown = Self.shows(new)
        switch new {
        case .idle:
            stop()
            // Nothing stays mounted in the hidden overlay (a whole sidebar, registered for drops); `arming` mounts it
            // again where it will open.
            anchor = nil
            pointer = nil
            hovered = nil
            neighbours = []
            strength = 0
        case .arming:
            onPrepare?()
            // Mount the rail's copy where it will open, so its first frame is whole.
            if let rect = surface?.windowRect { anchor = rect }
        case .open:
            if !wasShown { Self.scroll(overlayList, like: surface?.list) }
            if effect == .magnify { withAnimation(RailHover.grow) { strength = 1 } }
        case .leaving:
            break
        case .closing:
            if effect == .expand { Self.scroll(surface?.list, like: overlayList) }
            // The carousel keeps its tiles while it fades and shrinks back; they are let go at `idle`.
            if effect == .magnify { withAnimation(RailHover.shrink) { strength = 0 } }
        }
        if wasShown != isShown {
            passingThrough = !isShown
            onPassThrough?(!isShown)
            onOverlay?(isShown)
        }
        if new == .idle, old != .idle { onRelease?() }
    }

    /// The rail's list of tiles (its scroll view, window coordinates), clipped to the rail.
    private func tilesRect(_ rail: CGRect) -> CGRect? {
        guard let scroll = surface?.list.view?.enclosingScrollView, scroll.window != nil else { return nil }
        return scroll.convert(scroll.bounds, to: nil).intersection(rail)
    }

    /// Where the pointer keeps the effect: Expand's sidebar, or the tab row; both grow away from the window's edge.
    private func zone(_ rail: CGRect, onRight: Bool) -> CGRect? {
        switch effect {
        case .expand:
            let width = expandWidth()
            let base = anchor ?? rail
            return CGRect(x: onRight ? base.maxX - width : base.minX, y: base.minY, width: width, height: base.height)
        case .magnify:
            // The rows: the hovered one and the smaller ones beside it.
            guard let tile = hovered?.tile else { return nil }
            let rows = neighbours.reduce(tile) { $0.union($1.tile) }
            let width = max(tile.width, rowWidth)
            return CGRect(x: onRight ? tile.maxX - width : tile.minX, y: rows.minY, width: width, height: rows.height)
        case nil:
            return nil
        }
    }

    /// The pointer in window coordinates, or nil when it is off this window (another window in front, the app inactive).
    private func pointerLocation(in window: NSWindow) -> NSPoint? {
        #if DEBUG
        if let pretend = pretendPointer { return pretend }
        #endif
        guard NSApp.isActive, window.isVisible else { return nil }
        let number = NSWindow.windowNumber(at: NSEvent.mouseLocation, belowWindowWithWindowNumber: 0)
        guard let front = NSApp.window(withWindowNumber: number), front === window || front.parent === window else { return nil }
        return window.mouseLocationOutsideOfEventStream
    }

    private static func shows(_ phase: Phase) -> Bool {
        switch phase {
        case .open, .leaving, .closing: true
        case .idle, .arming: false
        }
    }

    private static func same(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 0.5 && abs(a.minY - b.minY) < 0.5 && abs(a.width - b.width) < 0.5 && abs(a.height - b.height) < 0.5
    }

    /// Scrolls one rail list to where the other is, so Expand's sidebar shows the same rows the rail did.
    private static func scroll(_ target: RailSpace?, like source: RailSpace?) {
        guard let from = source?.view?.enclosingScrollView, let to = target?.view?.enclosingScrollView else { return }
        to.contentView.scroll(to: from.contentView.bounds.origin)
        to.reflectScrolledClipView(to.contentView)
    }
}

/// What a rail item is, for the tab row Magnify shows for it.
enum RailItemKind: Hashable {
    case tab(String)
    case folder(String)
    case newTab
}

struct RailItemKey: Hashable {
    let surface: String
    let kind: RailItemKind
}

enum RailMagnifyRole {
    case hovered
    case neighbour
}

/// The item under the pointer: its 36 pt tile in window coordinates and its icon's size.
struct RailHoveredItem: Equatable {
    let key: RailItemKey
    let tile: CGRect
    let iconSize: CGFloat
}

private struct RailItemEntry {
    weak var space: RailSpace?
    var frame: CGRect
    var iconSize: CGFloat
}
