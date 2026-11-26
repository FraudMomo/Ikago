import AppKit
import SwiftUI

/// The icon sidebar's hover effects (Settings ▸ Appearance ▸ Layout ▸ Window and Sidebar ▸ Icon sidebar on hover).
///
/// - Magnify: the icons near the pointer grow in place, like the Dock (`railMagnify`), and the tile under the pointer
///   becomes a tab row over the page with its name (`RailMagnifyLayer`).
/// - Expand: the rail widens over the page with each name beside its icon (`RailExpandPanel`).
///
/// Both draw over the page in a window of their own (`RailOverlay`): AppKit sends pointer moves to every tracking area
/// under the pointer whatever covers it, so the page under them went on hovering; the window server sends the pointer
/// to the overlay only where it draws. When they open and close is `RailHoverModel`'s state machine, and nothing else.
/// Off by default, and off under Reduce Motion.
enum RailHover {
    /// Expand's width: room for each row's name beside its icon.
    static let expandedWidth: CGFloat = 240
    /// The icon under the pointer at its largest (a 16 pt icon grows to 24 pt, inside its 36 pt tile), and the ones
    /// just above and below it.
    static let largest: CGFloat = 1.5
    static let neighbour: CGFloat = 1.18
    /// The carousel moving from tile to tile: the icons growing and shrinking and the rows gliding, on one spring.
    static let glide = Animation.spring(response: 0.2, dampingFraction: 0.86)
    /// Magnify easing in as the pointer arrives, and out as it leaves.
    static let grow = Animation.easeOut(duration: 0.15)
    static let shrink = Animation.easeInOut(duration: 0.16)
    /// Expand opening: a decelerating curve (fast start, soft landing), as Chrome-style vertical tabs widen.
    static let reveal = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.17)
    static let conceal = Animation.timingCurve(0.3, 0, 0.8, 0.15, duration: 0.12)
    /// How long the effects take to settle back onto the rail, after which the overlay goes.
    static let settle: Duration = .milliseconds(180)
    /// How long the pointer rests on the rail before it widens, so crossing it to the window's edge doesn't flash it.
    static let expandDelay: Duration = .milliseconds(50)
    /// How long the effects stay after the pointer leaves them, to forgive a slip.
    static let leaveGrace: Duration = .milliseconds(120)

    /// An icon's scale for its place in Magnify's carousel, at `strength` (0 at rest, 1 grown).
    static func scale(_ role: RailMagnifyRole?, strength: CGFloat) -> CGFloat {
        let full: CGFloat = switch role {
        case .hovered: largest
        case .neighbour: neighbour
        case nil: 1
        }
        return 1 + (full - 1) * strength
    }
}

/// One host's coordinate space in a rail: the rail itself, and its list, which scrolls in its own `NSHostingView`.
/// Views inside measure their frames in it with SwiftUI's layout and the space's anchor view turns those into window
/// coordinates live, scroll included.
@MainActor
final class RailSpace {
    let name: String
    weak var view: NSView?
    weak var surface: RailSurface?
    init(_ name: String) { self.name = name }

    /// `local` in window coordinates (AppKit's, from the bottom).
    func windowRect(_ local: CGRect) -> CGRect? {
        guard let view, view.window != nil else { return nil }
        return view.convert(local, to: nil)
    }
}

/// One rail on screen: the docked one, or one slid in from the window's edge, with its spaces.
@MainActor
final class RailSurface {
    let rail = RailSpace("rail")
    let list = RailSpace("rail.list")
    /// Names this rail's tracking view among the places the pointer can be.
    let id = UUID().uuidString
    init() {
        rail.surface = self
        list.surface = self
    }

    var isOnScreen: Bool { rail.view?.window != nil }

    /// The rail's frame in window coordinates (AppKit's).
    var windowRect: CGRect? {
        guard let view = rail.view, view.window != nil else { return nil }
        return view.convert(view.bounds, to: nil)
    }
}

// MARK: - Magnify

private struct RailHoverModelKey: EnvironmentKey { static let defaultValue: RailHoverModel? = nil }
private struct RailSpaceKey: EnvironmentKey { static let defaultValue: RailSpace? = nil }
private struct RailItemsHiddenKey: EnvironmentKey { static let defaultValue = false }
private struct RailCopyKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// Set while Magnify is on: the rail's icons grow near the pointer.
    var railHover: RailHoverModel? {
        get { self[RailHoverModelKey.self] }
        set { self[RailHoverModelKey.self] = newValue }
    }
    var railSpace: RailSpace? {
        get { self[RailSpaceKey.self] }
        set { self[RailSpaceKey.self] = newValue }
    }
    /// Inside Magnify's copy of the rail in the overlay (`SidebarRail.magnified`).
    var railCopy: Bool {
        get { self[RailCopyKey.self] }
        set { self[RailCopyKey.self] = newValue }
    }
    /// Inside a shut group: its tiles are mounted but not on screen, so the pointer is never on them.
    var railItemsHidden: Bool {
        get { self[RailItemsHiddenKey.self] }
        set { self[RailItemsHiddenKey.self] = newValue }
    }
}

extension View {
    /// A rail icon under Magnify: it grows in place near the pointer (scaled, never laid out larger, so the tiles and
    /// the pointer's measure of them stay put). The copy in the overlay draws it while Magnify shows; the rail's own
    /// steps aside.
    func railMagnify(_ kind: RailItemKind, iconSize: CGFloat) -> some View { modifier(RailMagnify(kind: kind, iconSize: iconSize)) }

    /// Makes this view a rail coordinate space: icons inside measure themselves against it.
    func railSpace(_ space: RailSpace, onScroll: (() -> Void)? = nil) -> some View {
        coordinateSpace(.named(space.name))
            .background(RailSpaceAnchor(space: space, onScroll: onScroll))
            .environment(\.railSpace, space)
    }
}

private struct RailMagnify: ViewModifier {
    let kind: RailItemKind
    let iconSize: CGFloat
    @Environment(\.railHover) private var model
    @Environment(\.railSpace) private var space
    @Environment(\.railItemsHidden) private var hidden
    @Environment(\.railCopy) private var copy
    @State private var frame: CGRect = .zero
    @State private var owner = UUID()

    func body(content: Content) -> some View {
        if let model, let space, let surface = space.surface {
            let key = RailItemKey(surface: surface.id, kind: kind)
            let scale = RailHover.scale(model.role(of: key), strength: model.strength)
            content
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(space.name)) } action: { new in
                    frame = new
                    if !hidden { model.register(key, owner: owner, space: space, frame: new, iconSize: iconSize) }
                }
                .onChange(of: hidden, initial: true) { _, now in
                    if now { model.unregister(key, owner: owner) } else { model.register(key, owner: owner, space: space, frame: frame, iconSize: iconSize) }
                }
                .onDisappear { model.unregister(key, owner: owner) }
                .scaleEffect(scale)
                .animation(RailHover.glide, value: scale)
                // The rail's own icon steps aside while the copy's lies over it; not 0, or SwiftUI stops hit-testing.
                .opacity(!copy && model.covered && model.surface === surface ? 0.001 : 1)
        } else {
            content
        }
    }
}

/// The view a `RailSpace` converts through. It fills the space's view exactly, flipped like SwiftUI, and reports when
/// the list scrolls (the clip view's bounds move, the icons' own frames don't).
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

/// Follows the pointer over a view, in window coordinates (nil when it leaves). AppKit's tracking area: SwiftUI's hover
/// misses moves across hosts and a pointer arriving fast. The rail's effects use it only to start
/// (`RailHoverModel.pointerMoved`); their state machine reads the pointer itself from then on.
struct RailPointerTracker: FillingViewRepresentable {
    let onMove: (NSPoint?) -> Void
    func makeNSView(context: Context) -> RailTrackingView { RailTrackingView() }
    func updateNSView(_ view: RailTrackingView, context: Context) { view.onMove = onMove }
}

/// Tracks in any window of the active app, checks every report against where the view is now, and catches up with a
/// pointer already inside when the view arrives, changes size or its window comes forward, none of which AppKit
/// reports as an entry.
final class RailTrackingView: NSView {
    var onMove: (NSPoint?) -> Void = { _ in }
    private var isInside = false
    private var observers: [NSObjectProtocol] = []

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect],
                                       owner: self, userInfo: nil))
        syncSoon()
    }

    override func mouseEntered(with event: NSEvent) { follow(event.locationInWindow) }
    override func mouseMoved(with event: NSEvent) { follow(event.locationInWindow) }
    override func mouseExited(with event: NSEvent) { leave() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Leaving its window (always before it goes away) removes them.
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        guard let window else { leave(); return }
        let center = NotificationCenter.default
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didBecomeMainNotification] {
            observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.sync() }
            })
        }
        observers.append(center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.leave() }
        })
        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.sync() }
        })
        syncSoon()
    }

    private func syncSoon() {
        DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated { self?.sync() } }
    }

    /// Whether the pointer is over this view now, in this window and not under another window in front of it.
    private func sync() {
        guard let window, NSApp.isActive, !isHiddenOrHasHiddenAncestor else { leave(); return }
        let point = window.mouseLocationOutsideOfEventStream
        let frontmost = NSWindow.windowNumber(at: NSEvent.mouseLocation, belowWindowWithWindowNumber: 0) == window.windowNumber
        if frontmost && contains(point) { report(point) } else { leave() }
    }

    private func contains(_ windowPoint: NSPoint) -> Bool {
        visibleRect.contains(convert(windowPoint, from: nil))
    }

    private func follow(_ point: NSPoint) {
        if contains(point) { report(point) } else { leave() }
    }

    private func report(_ point: NSPoint) {
        isInside = true
        onMove(point)
    }

    private func leave() {
        guard isInside else { return }
        isInside = false
        onMove(nil)
    }
}
