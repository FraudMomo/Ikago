#if DEBUG
import AppKit

@MainActor
enum TopBarLayoutChecks {
    static func run(_ browser: BrowserWindowController) async {
        let state = browser.state, original = state.snapshot(), size = browser.window?.contentView?.frame.size
        var failures = 0
        func check(_ value: Bool, _ message: String) {
            print("IKTEST topbarlayout \(value ? "PASS" : "FAIL") \(message)")
            if !value { failures += 1 }
        }
        defer {
            browser.dismissCommandPalette(); state.apply(original)
            if let size { browser.window?.setContentSize(size) }
        }
        BookmarkBarChecks.seed(browser)
        state.tabLayout = .horizontal
        state.useGlass = false; state.showsTopBarEssentials = false; state.showsBookmarksBar = false
        for index in 0..<16 {
            state.tabs.append(TabItem(url: "https://top-layout.invalid/\(index)", title: "A readable Top Bar tab \(index)", spaceID: state.activeSpaceID))
        }
        if let tab = state.tabs.last { state.select(tab.id) }
        for style in TopTabStyle.allCases {
            state.topTabStyle = style
            for floating in [false, true] {
                state.barRounded = floating
                for width in [1100.0, 420.0] {
                    browser.window?.setContentSize(NSSize(width: width, height: 750))
                    try? await Task.sleep(for: .milliseconds(550))
                    let strip = LayoutChecks.frames["tab-viewport"], active = LayoutChecks.frames["active-tab"]
                    if strip.flatMap({ viewport in active.map { $0.minX >= viewport.minX - 4 && $0.maxX <= viewport.maxX + 4 } }) != true {
                        print("IKTEST Top Bar bounds style=\(style) floating=\(floating) active=\(String(describing: active)) viewport=\(String(describing: strip))")
                    }
                    check(strip.map { $0.minX >= 0 && $0.maxX <= width + 1 } == true,
                          "\(style)/floating=\(floating) tabs stay within \(Int(width)) pt")
                    check(strip.flatMap { viewport in active.map { $0.minX >= viewport.minX - 4 && $0.maxX <= viewport.maxX + 4 } } == true,
                          "\(style) active tab remains visible after resizing")
                    if style == .separate {
                        let address = LayoutChecks.frames["top-address"]
                        check(address.map { $0.width >= 120 && $0.minX >= 80 && $0.maxX <= width + 1 && abs($0.height - 32) < 1 } == true,
                              "Top Bar address field stays usable without covering the window controls")
                        check(LayoutChecks.frames["top-toolbar"].flatMap { toolbar in strip.map { $0.minY >= toolbar.maxY - 1 } } == true,
                              "Separate tabs sit below the toolbar")
                    }
                }
            }
        }
        browser.window?.setContentSize(NSSize(width: 1100, height: 750))
        for style in TopTabStyle.allCases {
            state.topTabStyle = style
            for height in [44.0, 60.0] {
                state.browserPreferences.topToolbarHeight = height; state.browserPreferences.topTabBarHeight = height - 16
                // Long enough for the other tab style's outgoing view to stop reporting its frame.
                try? await Task.sleep(for: .milliseconds(1000))
                let row = LayoutChecks.frames[style == .separate ? "top-toolbar" : "island"]
                let tabs = style == .separate ? LayoutChecks.frames["tab-viewport"] : nil
                check(row.map { abs($0.height - height) < 1 } == true && (style == .compact || tabs.map { abs($0.height - (height - 16)) < 1 } == true),
                      "\(style) toolbar and tab bar heights follow the setting (\(Int(height)) pt)")
            }
        }
        state.browserPreferences.topToolbarHeight = nil; state.browserPreferences.topTabBarHeight = nil
        state.barRounded = true; state.topTabStyle = .separate
        try? await Task.sleep(for: .milliseconds(400))
        check(LayoutChecks.frames["top-header"].map { header in
            LayoutChecks.frames["top-toolbar"].map { $0.minY >= header.minY + BrowserState.topBarFloatingMargin - 0.5
                && $0.minX >= header.minX + BrowserState.topBarFloatingMargin - 0.5 } ?? false } == true,
              "floating toolbar is detached from the window edges by its margin")
        state.barRounded = false; state.topTabStyle = .separate
        browser.window?.setContentSize(NSSize(width: 1100, height: 750))
        for mode in [ColorMode.light, .dark] {
            state.colorMode = mode
            for colors in [SpaceColors.standard, SpaceColors(light: 0x101050, dark: 0xFFF0A0)] {
                state.setColors(colors, for: state.activeSpaceID)
                let tint = state.topBarPalette.nsTint.usingColorSpace(.sRGB)!
                let luminance = 0.2126 * tint.redComponent + 0.7152 * tint.greenComponent + 0.0722 * tint.blueComponent
                check(mode == .dark ? luminance < 0.35 : luminance > 0.65,
                      "\(mode) Top Bar chrome retains readable native contrast with arbitrary Space colors")
            }
        }
        state.addressStyle = .integrated
        if let pin = state.pinnedTabs.first {
            state.select(pin.id)
            try? await Task.sleep(for: .milliseconds(250))
            browser.showCommandPalette(newTab: false)
            try? await Task.sleep(for: .milliseconds(400))
            check(browser.chrome.inlineAddress && browser.window?.firstResponder is NSTextView,
                  "Separate address field accepts Cmd+L for a hidden pin")
            check(ExtensionManager.shared.anchors["address"]?.window === browser.window,
                  "Top Bar registers the dedicated address field as an extension popup anchor")
            browser.dismissCommandPalette()
        }
        state.showsBookmarksBar = true
        state.showsTopBarEssentials = true
        try? await Task.sleep(for: .milliseconds(500))
        check(LayoutChecks.frames["bookmarks-bar"].flatMap { bookmarks in
            LayoutChecks.frames["connected-tab-row"].map { abs(bookmarks.minY - $0.maxY) < 1 }
        } == true, "bookmarks touch the Top Bar tab row on the same surface")
        print("IKTEST topbarlayoutchecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }
}
#endif
