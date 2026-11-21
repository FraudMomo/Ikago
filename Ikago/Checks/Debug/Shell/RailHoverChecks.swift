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
        let top = SidebarRail.lightsHeight + 8 + 16
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
        point(onRail: false, effect: .expand)
        try? await Task.sleep(for: settled)

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
