#if DEBUG
import AppKit

/// Exercises real commands and native geometry, including switching a live page into floating mode.
@MainActor
enum TopBarPolishChecks {
    static func run(_ browser: BrowserWindowController, base: String) async {
        let state = browser.state, original = state.snapshot(), size = browser.window?.contentView?.frame.size
        var failures = 0
        func check(_ condition: Bool, _ message: String) {
            print("IKTEST topbarpolish \(condition ? "PASS" : "FAIL") \(message)")
            if !condition { failures += 1 }
        }
        defer {
            browser.dismissCommandPalette(); state.apply(original)
            if let size { browser.window?.setContentSize(size) }
        }
        NSApp.activate()
        browser.window?.makeKeyAndOrderFront(nil)
        browser.window?.setContentSize(NSSize(width: 1100, height: 750))
        state.newTabMode = .commandBar
        state.addressStyle = .floating
        state.newTabPosition = .top
        state.linkTabPosition = .beforeCurrent
        state.focusAddressBarOnNewTab = false
        state.showsBookmarksBar = false; state.showsTopBarEssentials = false
        for layout in [TabLayout.horizontal] {
            state.tabLayout = layout
            for style in TopTabStyle.allCases where layout == .horizontal || style == .separate {
                browser.dismissCommandPalette(); state.topTabStyle = style
                let count = state.tabs.count
                browser.newTab()
                try? await Task.sleep(for: .milliseconds(500))
                check(state.tabs.count == count + 1 && state.looseTabs.last?.id == state.activeTabID,
                      "\(layout)/\(style) creates one tab at the right despite Sidebar newest-on-top")
                check(browser.chrome.inlineAddress && !browser.chrome.showPalette && browser.palette.mode == .currentTab,
                      "top layout edits the new tab in place despite Sidebar floating address preference")
                func focusedField(_ view: NSView) -> FocusingTextField? {
                    if let field = view as? FocusingTextField, !field.isHiddenOrHasHiddenAncestor,
                       field.currentEditor() === browser.window?.firstResponder { return field }
                    return view.subviews.lazy.compactMap { focusedField($0) }.first
                }
                let field = browser.window?.contentView.flatMap { focusedField($0) }
                check(field?.currentEditor() === browser.window?.firstResponder,
                      "new top tab owns the keyboard with the Sidebar focus toggle off")
                if let editor = field?.currentEditor() as? NSTextView {
                    check(!editor.drawsBackground && field?.focusRingType == NSFocusRingType.none,
                          "native editor cannot paint a rectangular background or focus ring")
                } else { check(false, "native address editor exists") }
                browser.dismissCommandPalette()
                if let opener = state.activeTab {
                    let link = state.newTabFromLink(url: "https://link.example/", opener: opener, select: false)
                    check(link.flatMap { child in state.tabs.firstIndex(where: { $0.id == child.id }) }
                          == state.tabs.firstIndex(where: { $0.id == opener.id }).map { $0 + 1 },
                          "top-layout links follow the opener despite Sidebar before-current preference")
                }
            }
        }
        check(state.newTabPosition == .top && state.linkTabPosition == .beforeCurrent && state.addressStyle == .floating,
              "top layouts preserve the saved Sidebar preferences")
        if URL(string: base)?.host == "127.0.0.1" {
            state.tabLayout = .horizontal; state.topTabStyle = .compact
            state.barRounded = false
            browser.open(base + "/", inNewTab: true)
            try? await Task.sleep(for: .seconds(1))
            let page = browser.activeController?.page
            for style in TopTabStyle.allCases {
                state.topTabStyle = style
                for floating in [true, false, true] {
                    state.barRounded = floating
                    try? await Task.sleep(for: .milliseconds(550))
                    check(browser.activeController?.page === page && page != nil,
                          "floating/docked switch preserves the live page")
                    if let content = LayoutChecks.frames["content"], let header = LayoutChecks.frames["top-header"] {
                        check(floating ? content.minY < header.maxY - 10 : content.minY >= header.maxY - 1,
                              "\(style)/floating=\(floating) page underlaps only the floating header")
                    } else { check(false, "rendered page and Top Bar header frames exist") }
                }
            }
        }
        print("IKTEST topbarpolishchecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }
}
#endif
