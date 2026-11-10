#if DEBUG
import AppKit

@MainActor
enum TabOverflowChecks {
    static func run(_ controller: BrowserWindowController) async {
        var failures = 0
        func check(_ value: Bool, _ title: String) {
            print("IKTEST taboverflow \(value ? "PASS" : "FAIL") \(title)")
            if !value { failures += 1 }
        }
        if controller.state.tabs.count < 20 { LayoutChecks.seed(controller) }
        let state = controller.state
        state.tabLayout = .horizontal
        state.useGlass = false
        state.frameInset = 0
        state.barHeight = 28
        state.chromeLayout = ChromeLayout()
        controller.window?.setContentSize(NSSize(width: 1100, height: 750))
        // Enough tabs that even compacted (favicon-width) tabs overflow the strip.
        for index in state.regularTabs.count..<80 {
            state.tabs.append(TabItem(url: "https://overflow.invalid/\(index)", title: "Overflow tab \(index)", spaceID: state.activeSpaceID))
        }
        for floating in [false, true] {
            state.barRounded = floating
            // Allow the native scroll hierarchy to settle after switching bar modes.
            try? await Task.sleep(for: .milliseconds(1200))
            guard let strip = nativeStrip(controller), let document = strip.documentView else {
                check(false, "native horizontal scroll view exists"); continue
            }
            check(document.bounds.width > strip.contentView.bounds.width + 1000,
                  "tabs past their compacted minimum overflow instead of shrinking further, floating=\(floating)")
            await scroll(controller, to: 0)
            check(!LayoutChecks.tabEdges.leading && LayoutChecks.tabEdges.trailing,
                  "only the right edge fades at the start")
            await scroll(controller, to: 0.5)
            check(strip.contentView.bounds.minX > 100 && LayoutChecks.tabEdges.leading && LayoutChecks.tabEdges.trailing,
                  "native scrolling moves tabs and fades both edges in the middle")
            await scroll(controller, to: 1)
            check(LayoutChecks.tabEdges.leading && !LayoutChecks.tabEdges.trailing,
                  "only the left edge fades at the end, leaving last-tab controls clear")
        }
        await scroll(controller, to: 0)
        controller.openPage(.history)
        try? await Task.sleep(for: .milliseconds(500))
        let strip = nativeStrip(controller)
        let frame = strip.map { $0.convert($0.bounds, to: controller.window?.contentView) }
        let active = LayoutChecks.frames["active-tab"]
        check(frame.flatMap { viewport in active.map { $0.minX >= viewport.minX - 4 && $0.maxX <= viewport.maxX + 4 } } == true,
              "selecting a new tab reveals it in the overflowing strip")
        let regularWidths = state.regularTabs.compactMap { LayoutChecks.frames["regular-tab-\($0.id)"]?.width }
        let activeWidth = active?.width ?? 0
        check(regularWidths.count > 10 && activeWidth >= TabStripLayout.minTab - 1
              && regularWidths.filter { $0 < TabStripLayout.iconOnlyWidth }.count >= regularWidths.count - 1,
              "crowded inactive tabs compact to favicons beside a readable active tab")
        let widthBeforeSelection = strip?.documentView?.bounds.width
        if let settings = state.tabs.first(where: { $0.url == InternalPage.settings.url }) { state.select(settings.id) }
        try? await Task.sleep(for: .milliseconds(400))
        check(widthBeforeSelection == nativeStrip(controller)?.documentView?.bounds.width
              && abs((LayoutChecks.frames["active-tab"]?.width ?? 0) - activeWidth) < 1,
              "switching tabs hands the readable width to the new tab and leaves the strip width unchanged")
        if let folder = state.spaceFolders.last, let member = state.tabs(in: folder).last {
            func isRevealed(_ key: String) -> Bool {
                guard let strip = nativeStrip(controller), let window = controller.window,
                      let item = LayoutChecks.frames[key] else { return false }
                let viewport = strip.convert(strip.bounds, to: window.contentView)
                return item.minX >= viewport.minX - 4 && item.maxX <= viewport.maxX + 4
            }
            state.select(member.id)
            try? await Task.sleep(for: .milliseconds(500))
            check(isRevealed("active-tab"), "selecting a grouped tab reveals the member inside its group surface")
            state.toggleFolder(folder.id)
            try? await Task.sleep(for: .milliseconds(500))
            check(isRevealed("folder-\(folder.id)"), "collapsing the active group reveals its header")
            state.toggleFolder(folder.id)
            try? await Task.sleep(for: .milliseconds(500))
            check(isRevealed("active-tab"), "expanding the active group reveals its selected member again")
        }
        if let current = state.activeTab {
            state.tabs = [current]; state.folders = []; state.splits = []
        }
        try? await Task.sleep(for: .milliseconds(500))
        let hiddenStrip = state.topTabStyle == .separate && !state.topBarShowsTabStrip
        check(hiddenStrip || (!LayoutChecks.tabEdges.leading && !LayoutChecks.tabEdges.trailing), "no edge fade when all tabs fit")
        print("IKTEST taboverflowchecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }

    static func scroll(_ controller: BrowserWindowController, to fraction: Double) async {
        guard let strip = nativeStrip(controller), let document = strip.documentView else { return }
        let maximum = max(0, document.bounds.width - strip.contentView.bounds.width)
        strip.contentView.scroll(to: NSPoint(x: maximum * min(1, max(0, fraction)), y: strip.contentView.bounds.minY))
        strip.reflectScrolledClipView(strip.contentView)
        try? await Task.sleep(for: .milliseconds(250))
    }

    private static func nativeStrip(_ controller: BrowserWindowController) -> NSScrollView? {
        func find(_ view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView, !scroll.isHiddenOrHasHiddenAncestor, scroll.bounds.height < 70 { return scroll }
            for child in view.subviews { if let found = find(child) { return found } }
            return nil
        }
        return controller.window?.contentView.flatMap(find)
    }
}
#endif
