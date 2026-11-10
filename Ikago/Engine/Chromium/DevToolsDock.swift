import AppKit

/// Docks Chromium's DevTools beside the page: on the left, right, top or
/// bottom, resizable by a divider between the two, with a slim bar to change sides or close it. DevTools
/// stays a separate native window, because CEF crashes if it is embedded as a view in this style, but
/// with no frame, moving with Ikago's window and covering the area the dock takes from the page.
@MainActor
final class DevToolsDock {
    enum Side: String, CaseIterable { case left, right, top, bottom }

    /// Where each part goes inside the page's host view (non-flipped coordinates).
    struct Frames: Equatable { var page, divider, bar, tools: NSRect }

    private weak var page: NSView?
    private var tools: NSWindow?
    private var observer: NSObjectProtocol?
    private var divider: DevToolsDivider?
    private var bar: DevToolsBar?
    /// Asks the page to close DevTools (the same as ⌥⌘I).
    var close: () -> Void = {}

    static let minimumTools: CGFloat = 220, minimumPage: CGFloat = 240, defaultShare: CGFloat = 0.42
    private static let sideKey = "DevToolsDockSide", shareKey = "DevToolsDockShare"

    /// One side and size for every tab, saved for the next launch: DevTools opens where it was last left.
    var side: Side { Side(rawValue: UserDefaults.standard.string(forKey: Self.sideKey) ?? "") ?? .right }
    private var share: CGFloat {
        get {
            let saved = UserDefaults.standard.double(forKey: Self.shareKey)
            return saved > 0 && saved < 1 ? saved : Self.defaultShare
        }
        set { UserDefaults.standard.set(newValue, forKey: Self.shareKey) }
    }

    init(page: NSView) { self.page = page }

    func attach(_ window: NSWindow?) {
        guard let window else { return detach() }
        tools = window
        Self.removeFrame(of: window)
        observer = NotificationCenter.default.addObserver(forName: NSWindow.didUpdateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        }
        layout()
    }

    /// No Chromium frame, and marked as Ikago's dock so `ChromiumWindowGuard` leaves it alone.
    static func removeFrame(of window: NSWindow) {
        window.identifier = ChromiumWindowGuard.dockedDevTools
        window.styleMask = [.borderless]
        window.hasShadow = false
        window.isMovable = false
        window.alphaValue = 1
    }

    func move(to side: Side) {
        UserDefaults.standard.set(side.rawValue, forKey: Self.sideKey)
        layout()
    }

    /// The layout for a side and share of the host: the bar heads the DevTools area, and the divider
    /// sits in its own gap, so the page never competes with it for the mouse.
    static func frames(in bounds: NSRect, side: Side, share: CGFloat) -> Frames {
        let horizontal = side == .left || side == .right
        let length = horizontal ? bounds.width : bounds.height
        let gap = DevToolsDivider.thickness
        let toolsLength = max(0, min(max(length * share, minimumTools), length - minimumPage - gap))
        let pageLength = max(0, length - toolsLength - gap)
        var page = bounds, divider = bounds, area = bounds
        switch side {
        case .right:
            page.size.width = pageLength
            divider = NSRect(x: bounds.minX + pageLength, y: bounds.minY, width: gap, height: bounds.height)
            area = NSRect(x: divider.maxX, y: bounds.minY, width: toolsLength, height: bounds.height)
        case .left:
            area = NSRect(x: bounds.minX, y: bounds.minY, width: toolsLength, height: bounds.height)
            divider = NSRect(x: area.maxX, y: bounds.minY, width: gap, height: bounds.height)
            page = NSRect(x: divider.maxX, y: bounds.minY, width: pageLength, height: bounds.height)
        case .bottom:
            area = NSRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: toolsLength)
            divider = NSRect(x: bounds.minX, y: area.maxY, width: bounds.width, height: gap)
            page = NSRect(x: bounds.minX, y: divider.maxY, width: bounds.width, height: pageLength)
        case .top:
            page.size.height = pageLength
            divider = NSRect(x: bounds.minX, y: bounds.minY + pageLength, width: bounds.width, height: gap)
            area = NSRect(x: bounds.minX, y: divider.maxY, width: bounds.width, height: toolsLength)
        }
        let barHeight = min(DevToolsBar.height, area.height)
        let bar = NSRect(x: area.minX, y: area.maxY - barHeight, width: area.width, height: barHeight)
        let tools = NSRect(x: area.minX, y: area.minY, width: area.width, height: area.height - barHeight)
        return Frames(page: page, divider: divider, bar: bar, tools: tools)
    }

    private func layout() {
        guard let tools, let page, let host = page.superview else { return }
        guard let parent = page.window, parent.isVisible, !page.isHiddenOrHasHiddenAncestor else {
            tools.parent?.removeChildWindow(tools)
            if tools.isVisible { tools.orderOut(nil) }
            divider?.isHidden = true
            bar?.isHidden = true
            return
        }
        var frames = Self.frames(in: host.bounds, side: side, share: share)
        if host.isFlipped { frames = Self.flip(frames, in: host.bounds) }
        if page.frame != frames.page {
            page.autoresizingMask = []
            page.frame = frames.page
        }
        place(dividerView(in: host), at: frames.divider)
        place(barView(in: host), at: frames.bar)
        bar?.side = side
        let screen = parent.convertToScreen(host.convert(frames.tools, to: nil))
        if tools.frame != screen { tools.setFrame(screen, display: true) }
        if tools.parent !== parent {
            parent.addChildWindow(tools, ordered: .above)
            tools.orderFront(nil)
        }
    }

    private static func flip(_ frames: Frames, in bounds: NSRect) -> Frames {
        func flipped(_ rect: NSRect) -> NSRect { NSRect(x: rect.minX, y: bounds.maxY - rect.maxY + bounds.minY, width: rect.width, height: rect.height) }
        return Frames(page: flipped(frames.page), divider: flipped(frames.divider), bar: flipped(frames.bar), tools: flipped(frames.tools))
    }

    private func place(_ view: NSView, at frame: NSRect) {
        view.isHidden = false
        if view.frame != frame { view.frame = frame; view.window?.invalidateCursorRects(for: view) }
    }

    private func dividerView(in host: NSView) -> DevToolsDivider {
        let view = divider ?? DevToolsDivider { [weak self] point in self?.dragged(to: point) }
        divider = view
        view.vertical = side == .left || side == .right
        if view.superview !== host { host.addSubview(view, positioned: .above, relativeTo: page) }
        return view
    }

    private func barView(in host: NSView) -> DevToolsBar {
        let view = bar ?? DevToolsBar { [weak self] side in self?.move(to: side) } close: { [weak self] in self?.close() }
        bar = view
        if view.superview !== host { host.addSubview(view, positioned: .above, relativeTo: page) }
        return view
    }

    private func dragged(to point: NSPoint) {
        guard let host = page?.superview else { return }
        let bounds = host.bounds
        let y = host.isFlipped ? bounds.maxY - point.y + bounds.minY : point.y
        let length: CGFloat, toolsLength: CGFloat
        switch side {
        case .right: length = bounds.width; toolsLength = bounds.maxX - point.x
        case .left: length = bounds.width; toolsLength = point.x - bounds.minX
        case .bottom: length = bounds.height; toolsLength = y - bounds.minY
        case .top: length = bounds.height; toolsLength = bounds.maxY - y
        }
        guard length > 0 else { return }
        share = min(max(toolsLength, Self.minimumTools), length - Self.minimumPage) / length
        layout()
    }

    private func detach() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        divider?.removeFromSuperview()
        divider = nil
        bar?.removeFromSuperview()
        bar = nil
        if let tools { tools.parent?.removeChildWindow(tools) }
        tools = nil
        guard let page, let host = page.superview else { return }
        page.frame = host.bounds
        page.autoresizingMask = [.width, .height]
    }
}
