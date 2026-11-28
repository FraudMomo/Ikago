#if DEBUG
import AppKit

/// A quick local check that the icon sidebar's hover effects (`RailHoverModel`) haven't broken badly: every run ends
/// back at `idle` once the pointer leaves, in every sidebar style, including a rail slid in from the window's edge
/// under Top Tabs. A pretend pointer drives the state machine; the real one is never moved. How it looks and feels is
/// for a person to judge.
@MainActor
enum RailHoverChecks {
    static func run(_ browser: BrowserWindowController) async {
        var failures = 0
        func check(_ value: Bool, _ title: String) {
            print("IKTEST railhover \(value ? "PASS" : "FAIL") \(title)")
            if !value { failures += 1 }
        }
        let state = browser.state, chrome = browser.chrome, model = chrome.rail
        let prefs = state.browserPreferences
        let saved = (prefs.railHover, prefs.sidebarCompact, state.sidebarVisible, prefs.sidebarTopTabs, prefs.sidebarEdgePeek)
        LayoutSwitch.set(tabs: false, state: state)
        state.browserPreferences.sidebarCompact = true
        state.sidebarVisible = true
        var made: [String] = []
        for index in 0..<4 { if let tab = state.newTab(url: "about:blank#rail\(index)", select: false) { made.append(tab.id) } }
        defer { model.pretendPointer = nil }

        /// Puts the pretend pointer in the middle of the rail (and starts the machine, as the rail's tracking view
        /// would), or off the window.
        func point(onRail: Bool, effect: RailHoverEffect, fromTop: CGFloat? = nil) {
            guard onRail, let surface = model.surface, let rect = surface.windowRect else {
                model.pretendPointer = .some(nil)
                return
            }
            model.pretendPointer = .some(NSPoint(x: rect.midX, y: fromTop.map { rect.maxY - $0 } ?? rect.midY))
            model.startForCheck(rail: surface, effect: effect)
        }
        let settled = Duration.milliseconds(900)

        // Magnify: open on the rail with a row for the tile under the pointer; idle once it leaves.
        state.browserPreferences.railHover = .magnify
        try? await Task.sleep(for: .milliseconds(900))
        check(model.surface?.windowRect != nil, "the rail is followed")
        // The new-tab tile, under the traffic lights; the first tab is just below it.
        // (Below the sidebar button when it sits at the top: a 32 pt tile and the 8 pt gap.)
        let top = SidebarRail.lightsHeight + 8 + (SidebarRail.togglesAtTop(state) ? 40 : 0) + 16
        point(onRail: true, effect: .magnify, fromTop: top)
        try? await Task.sleep(for: .milliseconds(400))
        check(model.phase == .open && model.strength == 1 && model.hovered?.key.kind == .newTab && model.rowOnScreen,
              "on the rail, Magnify opens with a row for the tile under the pointer")
        let first = (model.hovered, model.neighbours)
        check(!first.1.isEmpty && first.1.allSatisfy { $0.key != first.0?.key }, "the tiles beside it are its neighbours")
        // Moving within the tile changes nothing; moving to the next tile moves the carousel.
        point(onRail: true, effect: .magnify, fromTop: top + 8)
        try? await Task.sleep(for: .milliseconds(150))
        let still = model.hovered == first.0 && model.neighbours == first.1
        point(onRail: true, effect: .magnify, fromTop: top + 50)
        try? await Task.sleep(for: .milliseconds(150))
        check(still && model.hovered != first.0 && model.hovered?.key == first.1.last?.key,
              "the carousel stays put within a tile and moves to the next tile")
        point(onRail: false, effect: .magnify)
        try? await Task.sleep(for: settled)
        check(model.phase == .idle && model.strength == 0 && model.hovered == nil && model.neighbours.isEmpty && !model.overlayOnScreen,
              "off the rail, Magnify goes back to idle")
        // A drag that starts on the carousel's tiles: Magnify steps aside at once, but its copy of the rail (whose list is
        // the drag's source) stays mounted until the drag is over, then goes.
        point(onRail: true, effect: .magnify, fromTop: top + 50)
        try? await Task.sleep(for: .milliseconds(400))
        if model.phase == .open, let id = made.first {
            chrome.draggingTabID = id
            model.tick()
            let stepsAside = model.phase == .idle && model.passingThrough == true && model.anchor != nil
            point(onRail: false, effect: .magnify)
            try? await Task.sleep(for: .milliseconds(150))
            let kept = model.anchor != nil
            chrome.draggingTabID = nil
            model.tick()
            check(stepsAside && kept && model.anchor == nil, "a drag from Magnify's tiles keeps its list until the drag ends")
        } else {
            check(false, "Magnify opens before a drag")
        }
        point(onRail: false, effect: .magnify)
        try? await Task.sleep(for: settled)
        check(RailHover.scale(.hovered, strength: 1) > RailHover.scale(.neighbour, strength: 1) && RailHover.scale(.neighbour, strength: 1) > 1
              && RailHover.scale(nil, strength: 1) == 1, "the hovered icon grows most, its neighbours a little, others not at all")

        // Expand: out on the rail, always back to idle once the pointer leaves.
        state.browserPreferences.railHover = .expand
        try? await Task.sleep(for: .milliseconds(400))
        var back = true
        for _ in 0..<3 {
            point(onRail: true, effect: .expand)
            try? await Task.sleep(for: .milliseconds(300))
            let out = model.expanded && model.covered
            point(onRail: false, effect: .expand)
            try? await Task.sleep(for: settled)
            back = back && out && model.phase == .idle && !model.covered && !model.overlayOnScreen
        }
        check(back, "Expand widens on the rail and goes back to idle every time the pointer leaves")

        // The rail's traffic lights take clicks through the wider rail: over them the overlay lets the pointer through.
        point(onRail: true, effect: .expand)
        try? await Task.sleep(for: .milliseconds(300))
        let takes = model.passingThrough == false
        if let lights = model.lightsRect() {
            model.pretendPointer = .some(NSPoint(x: lights.midX, y: lights.midY))
            try? await Task.sleep(for: .milliseconds(100))
            check(takes && model.expanded && model.passingThrough == true, "over the traffic lights the wider rail lets clicks through")
        } else {
            check(false, "the rail holds the traffic lights")
        }
        // A tab dragged out of Expand's sidebar over the page: the effect stays out, but the overlay lets the drag through
        // to the browser window (split view's targets); back over the sidebar it takes it again.
        if let rail = model.surface?.windowRect, let window = browser.window, let id = made.first {
            chrome.draggingTabID = id
            model.pretendPointer = .some(NSPoint(x: window.frame.width * 0.7, y: rail.midY))
            try? await Task.sleep(for: .milliseconds(150))
            let overPage = model.passingThrough == true && model.expanded
            model.pretendPointer = .some(NSPoint(x: rail.minX + 120, y: rail.midY))
            try? await Task.sleep(for: .milliseconds(150))
            let overSidebar = model.passingThrough == false
            chrome.draggingTabID = nil
            check(overPage && overSidebar, "a drag over the page passes through the overlay; over Expand's sidebar it doesn't")
        }
        point(onRail: false, effect: .expand)
        try? await Task.sleep(for: settled)
        check(model.anchor == nil, "back at idle the overlay holds nothing")

        // Expand opens from anywhere on the rail, its buttons too (the full sidebar it brings has the same controls).
        if let toggle = LayoutChecks.frames["rail-sidebar-toggle"], let content = browser.window?.contentView {
            model.pretendPointer = .some(content.convert(NSPoint(x: toggle.midX, y: content.isFlipped ? toggle.midY : content.bounds.height - toggle.midY), to: nil))
            if let surface = model.surface { model.startForCheck(rail: surface, effect: .expand) }
            try? await Task.sleep(for: .milliseconds(400))
            check(model.expanded && model.passingThrough == false, "over the rail's sidebar button Expand opens and takes the pointer")
            point(onRail: false, effect: .expand)
            try? await Task.sleep(for: settled)
        }

        // The rail's own buttons (the sidebar button at the top, Tab Groups at the foot) take real clicks under Magnify:
        // the overlay window lies over them, and the window server gives it the click unless it lets the pointer through.
        // (Expand covers them with the full sidebar, which has the same controls.) A hidden group puts Tab Groups in the
        // foot.
        let hiddenGroup = state.createFolder(named: "Rail Hidden", with: made.last)
        _ = state.hideFolder(hiddenGroup.id)
        try? await Task.sleep(for: .milliseconds(500))
        let buttonNames = ["rail-sidebar-toggle", "rail-foot-tabGroups"]
        if let content = browser.window?.contentView {
            for effect in [RailHoverEffect.magnify] {
                state.browserPreferences.railHover = effect
                try? await Task.sleep(for: .milliseconds(400))
                for name in buttonNames {
                    guard let frame = LayoutChecks.frames[name] else { check(false, "the rail shows \(name)"); continue }
                    point(onRail: true, effect: effect)
                    try? await Task.sleep(for: .milliseconds(150))
                    let open = model.shown
                    model.pretendPointer = .some(content.convert(NSPoint(x: frame.midX, y: content.isFlipped ? frame.midY : content.bounds.height - frame.midY), to: nil))
                    try? await Task.sleep(for: .milliseconds(100))
                    check(open && model.passingThrough == true, "\(effect): over \(name) the overlay lets the click through")
                    point(onRail: false, effect: effect)
                    try? await Task.sleep(for: settled)
                }
            }
        }
        state.deleteFolder(hiddenGroup.id)

        // After switching sidebar styles back and forth, the effects open on the rail that is there and go back.
        var follows = true
        for (compact, visible) in [(false, true), (true, true), (true, false), (true, true), (false, true), (true, true)] {
            state.browserPreferences.sidebarCompact = compact ? true : nil
            state.sidebarVisible = visible
            try? await Task.sleep(for: .milliseconds(700))
            if !(compact && visible) {
                follows = follows && model.phase == .idle && !model.overlayOnScreen
                continue
            }
            follows = follows && model.surface?.isOnScreen == true
            point(onRail: true, effect: .expand)
            try? await Task.sleep(for: .milliseconds(300))
            follows = follows && model.expanded
            point(onRail: false, effect: .expand)
            try? await Task.sleep(for: settled)
            follows = follows && model.phase == .idle
        }
        check(follows, "after switching sidebar styles, the effects follow the rail on screen and go back")

        // Switching the sidebar away while the wider rail is out leaves nothing behind.
        point(onRail: true, effect: .expand)
        try? await Task.sleep(for: .milliseconds(300))
        let wasOut = model.expanded
        state.sidebarVisible = false
        try? await Task.sleep(for: .milliseconds(500))
        check(wasOut && model.phase == .idle && !model.overlayOnScreen, "hiding the sidebar while Expand is out takes it away")
        model.pretendPointer = .some(nil)

        // Top Tabs, sidebar hidden, the rail slid in from the edge: Expand opens on it, goes back, and the rail slides away.
        LayoutSwitch.set(tabs: true, state: state)
        state.browserPreferences.sidebarEdgePeek = true
        state.sidebarVisible = false
        try? await Task.sleep(for: .milliseconds(600))
        chrome.peek()
        try? await Task.sleep(for: .milliseconds(700))
        point(onRail: true, effect: .expand)
        try? await Task.sleep(for: .milliseconds(400))
        let peekOut = model.expanded
        chrome.peekHovered = false
        point(onRail: false, effect: .expand)
        try? await Task.sleep(for: .milliseconds(1400))
        check(peekOut && model.phase == .idle && !model.overlayOnScreen && !chrome.peeking,
              "Top Tabs: Expand on the slid-in rail goes back and the rail slides away")

        for id in made { state.closeTab(id) }
        LayoutSwitch.set(tabs: saved.3 == true, state: state)
        state.browserPreferences.railHover = saved.0
        state.browserPreferences.sidebarCompact = saved.1
        state.sidebarVisible = saved.2
        state.browserPreferences.sidebarEdgePeek = saved.4
        print("IKTEST railhoverchecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }
}
#endif
