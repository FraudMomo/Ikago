#if DEBUG
import AppKit

@MainActor
enum ProductPolishPreview {
    static func run(_ browser: BrowserWindowController) async {
        let state = browser.state, saved = state.snapshot()
        defer { state.apply(saved) }
        state.tabs = []; state.folders = []; state.splits = []
        state.useGlass = false; state.tabLayout = .horizontal
        state.barRounded = false; state.barAtBottom = false
        state.browserPreferences.pageIntelligence = true
        for title in ["Design Library", "Product Notes", "Reading List", "Research"] {
            let tab = state.newTab(url: "https://preview.invalid/\(UUID())", select: false)!
            tab.title = title
        }
        _ = state.newTab(url: InternalPage.history.url)
        for style in TopTabStyle.allCases {
            state.topTabStyle = style
            for mode in [ColorMode.light, .dark] {
                state.colorMode = mode
                try? await Task.sleep(for: .milliseconds(500))
                TestDriver.snapshot(browser.window, to: "/private/tmp/ikago-tabs-\(style.rawValue)-\(mode.rawValue).png")
            }
        }
    }
}
#endif
