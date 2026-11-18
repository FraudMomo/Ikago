#if DEBUG
import AppKit

/// The icon sidebar's hover effects (`RailHover`). Magnify: rows reach out by distance from the pointer and never move
/// or resize the rail's tiles, so nothing the pointer measures shifts under it; a shut group opens an island that stays
/// while the pointer is on it. Expand: the full sidebar comes out and goes back, and the page never moves for either.
@MainActor
enum RailHoverChecks {
    /// Holds a pretend pointer `y` points from the window's top over the rail's middle (nil: lets the real one back).
    static func point(_ y: CGFloat?, browser: BrowserWindowController) {
        let model = browser.chrome.rail, state = browser.state
        let effect = state.browserPreferences.railHover
        model.heldByCheck = y != nil
        guard let y, let height = browser.window?.contentView?.bounds.height else {
            model.move(nil, effect: effect)
            return
        }
        model.move(NSPoint(x: (model.railWindowRect?.midX ?? 32), y: height - y), effect: effect)
    }

    /// Holds the pretend pointer on the rail's `index`th tile from the top, or on its first group ("folder").
    static func pointTile(_ arg: String, browser: BrowserWindowController) {
        let model = browser.chrome.rail
        let height = browser.window?.contentView?.bounds.height ?? 0
        let tiles = model.tiles.keys.compactMap { tile in model.windowRect(tile).map { (tile, $0) } }.sorted { $0.1.maxY > $1.1.maxY }
        let target = arg == "folder" ? tiles.first { if case .folder = $0.0 { true } else { false } } : tiles.dropFirst(Int(arg) ?? 0).first
        if let target { point(height - target.1.midY, browser: browser) }
    }

    /// Titled tabs in the icon sidebar, a shut group holding tabs and a group inside it, for screenshots.
    static func seed(_ browser: BrowserWindowController, base: String) {
        let state = browser.state
        LayoutSwitch.set(tabs: false, state: state)
        state.browserPreferences.sidebarCompact = true
        let titles = ["Inbox", "Design review", "Swift Forums", "Release notes", "Weather", "Recipes", "Flights", "Maps"]
        let tabs = titles.compactMap { state.newTab(url: "\(base)/rail.html?title=\($0.replacingOccurrences(of: " ", with: "%20"))", select: false) }
        let research = state.createFolder(named: "Research", with: tabs[safe: 5]?.id)
        let papers = state.createFolder(named: "Papers", with: tabs[safe: 6]?.id, parentID: research.id)
        if let tab = tabs[safe: 7] { state.moveToFolder(tab.id, folderID: papers.id) }
        if let tab = tabs[safe: 4] { state.moveToFolder(tab.id, folderID: research.id) }
        if let index = state.folders.firstIndex(where: { $0.id == research.id }) { state.folders[index].isOpen = false }
    }

    static func run(_ browser: BrowserWindowController) async {
        var failures = 0
        func check(_ value: Bool, _ title: String) {
            print("IKTEST railhover \(value ? "PASS" : "FAIL") \(title)")
            if !value { failures += 1 }
        }
        let name: CGFloat = 120
        let peak = RailHover.reachOut(nameWidth: name, distance: 0)
        let near = RailHover.reachOut(nameWidth: name, distance: 40), nearAbove = RailHover.reachOut(nameWidth: name, distance: -40)
        check(peak > near && near > 0 && near == nearAbove, "the row under the pointer reaches furthest, its neighbours less, evenly")
        check(RailHover.reachOut(nameWidth: name, distance: RailHover.reach) == 0, "rows past the reach stay as tiles")
        let steps = stride(from: CGFloat(-90), through: 90, by: 1).map { RailHover.reachOut(nameWidth: name, distance: $0) }
        check(zip(steps, steps.dropFirst()).allSatisfy { abs($0 - $1) < 6 }, "a 1 pt move never jumps a row's length")

        let state = browser.state, model = browser.chrome.rail
        // The real cursor resting over the window would hover the cards and islands under test.
        browser.window?.ignoresMouseEvents = true
        defer { browser.window?.ignoresMouseEvents = false }
        let saved = (state.browserPreferences.railHover, state.browserPreferences.sidebarCompact)
        LayoutSwitch.set(tabs: false, state: state)
        state.browserPreferences.sidebarCompact = true
        var made: [String] = []
        for index in 0..<4 { if let tab = state.newTab(url: "about:blank#rail\(index)", select: false) { made.append(tab.id) } }
        let work = state.createFolder(named: "Work", with: made.first)
        let inner = state.createFolder(named: "Inner", with: made.dropFirst().first, parentID: work.id)
        if let index = state.folders.firstIndex(where: { $0.id == work.id }) { state.folders[index].isOpen = false }
        state.browserPreferences.railHover = .magnify
        try? await Task.sleep(for: .milliseconds(900))

        func pageFrame() -> NSRect? {
            func find(_ view: NSView) -> NSView? {
                if view is ContentContainerView { return view }
                return view.subviews.lazy.compactMap(find).first
            }
            return browser.window?.contentView.flatMap(find).map { $0.convert($0.bounds, to: nil) }
        }
        func tileFrames() -> [RailHoverModel.Tile: CGRect] {
            Dictionary(uniqueKeysWithValues: model.tiles.keys.compactMap { tile in model.windowRect(tile).map { (tile, $0) } })
        }
        let height = browser.window?.contentView?.bounds.height ?? 0
        let page = pageFrame()
        let resting = tileFrames()
        check(resting.count >= 4 && resting[.folder(work.id)] != nil, "the rail's tabs and groups report where they are (\(resting.count))")

        // Sweep the pointer down the rail: no tile moves or resizes at any point.
        let tabTiles = resting.filter { if case .tab = $0.key { true } else { false } }.values.sorted { $0.minY > $1.minY }
        var still = true
        if let first = tabTiles.first, let last = tabTiles.last {
            for y in stride(from: height - first.maxY, through: height - last.minY, by: 7) {
                point(y, browser: browser)
                try? await Task.sleep(for: .milliseconds(25))
                if tileFrames() != resting { still = false }
            }
        }
        check(still && !tabTiles.isEmpty, "moving along the rail never moves a tile, so the effect can't feed back")
        check(pageFrame() == page, "the page keeps its place and size while magnifying")

        // The leading row's card bridges the rail and the page: on it, off the rail, the rows hold.
        if let row = tabTiles.first {
            point(height - row.midY, browser: browser)
            try? await Task.sleep(for: .milliseconds(100))
            model.pillHover(true)
            point(nil, browser: browser)
            try? await Task.sleep(for: .milliseconds(450))
            check(model.pointer != nil, "on the leading row's card, off the rail, the rows stay out")
            model.pillHover(false)
            try? await Task.sleep(for: .milliseconds(450))
            check(model.pointer == nil, "off both the rail and the card, they go back")
        }

        // A shut group: a click opens its island, which stays while the pointer is on it.
        if let folder = resting[.folder(work.id)] {
            point(height - folder.midY, browser: browser)
            try? await Task.sleep(for: .milliseconds(450))
            check(model.island == nil, "resting on a group opens nothing; a click does")
            model.toggleIsland(work.id)
            try? await Task.sleep(for: .milliseconds(300))
            check(model.island == work.id, "a click on a shut group opens its island")
            point(nil, browser: browser)
            try? await Task.sleep(for: .milliseconds(450))
            check(model.island == work.id, "the island stays while the pointer is on it, off the rail")
            if let content = browser.window?.contentView {
                let x = BrowserState.sidebarRailWidth + CGFloat(state.frameInset) + 60
                let hit = content.hitTest(NSPoint(x: x, y: folder.minY - 24))
                check(hit.map { !String(describing: type(of: $0)).contains("WebView") } == true, "the island's card takes the pointer over the page")
            }
            model.islandHover(false)
            try? await Task.sleep(for: .milliseconds(450))
            check(model.island == nil, "leaving the island closes it")
            state.toggleFolder(work.id)
            try? await Task.sleep(for: .milliseconds(500))
            let inGroup = made.first.map { model.tiles[.tab($0)] == nil } ?? false
            check(state.railIslandOpens(work.id) && inGroup, "Magnify keeps even an open group shut in the rail: its tabs show in its island")
            point(nil, browser: browser)
        }
        _ = inner

        // Expand: the full sidebar comes out over the page and goes back.
        state.browserPreferences.railHover = .expand
        try? await Task.sleep(for: .milliseconds(300))
        point(height / 2, browser: browser)
        try? await Task.sleep(for: .milliseconds(500))
        check(model.expanded, "resting on the rail brings out the full sidebar")
        check(pageFrame() == page, "the page keeps its place and size while the sidebar is out")
        let hit = browser.window?.contentView?.hitTest(NSPoint(x: BrowserState.sidebarRailWidth + 60, y: height / 2))
        check(hit.map { !String(describing: type(of: $0)).contains("WebView") } == true, "the sidebar takes the pointer over the page")
        point(nil, browser: browser)
        try? await Task.sleep(for: .milliseconds(600))
        check(!model.expanded, "leaving the rail puts it back")
        let uncovered = browser.window?.contentView?.hitTest(NSPoint(x: BrowserState.sidebarRailWidth + 60, y: height / 2))
        check(uncovered.map { String(describing: type(of: $0)).contains("WebView") } == true, "put back, it lets the page have the pointer")
        // The wider rail stays mounted, hidden, over the rail: the rail's own list must still take the pointer.
        if let list = model.list?.view {
            let visible = list.visibleRect
            let point = list.convert(NSPoint(x: 32, y: visible.minY + 20), to: nil)
            let hit = browser.window?.contentView?.hitTest(point)
            check(hit?.enclosingScrollView === model.list?.view?.enclosingScrollView, "the hidden wider rail never takes the rail's clicks")
        }

        // A rail slid in from the edge stays while a group's island is open, and slides away once it closes.
        state.browserPreferences.railHover = .magnify
        try? await Task.sleep(for: .milliseconds(300))
        let chrome = browser.chrome
        chrome.peek()
        chrome.peekHovered = false
        model.toggleIsland(work.id)
        chrome.endPeek(after: .milliseconds(50))
        try? await Task.sleep(for: .milliseconds(300))
        check(chrome.peeking, "an open island keeps the slid-in sidebar out")
        model.closeIsland()
        try? await Task.sleep(for: .milliseconds(600))
        check(!chrome.peeking, "closing it lets the sidebar slide away")

        for id in made { state.closeTab(id) }
        state.deleteFolder(inner.id)
        state.deleteFolder(work.id)
        state.browserPreferences.railHover = saved.0
        state.browserPreferences.sidebarCompact = saved.1
        print("IKTEST railhoverchecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }
}
#endif
