import SwiftUI

extension BrowserRootView {
    /// A web app's window: a slim bar (navigation and the site's name beside the traffic lights) over its one page.
    var webAppLayout: some View {
        VStack(spacing: 0) {
            WebAppBar(state: state, commands: commands)
            contentCard
        }
        .background(WindowDragArea())
    }
}

/// Back, forward and reload at the start of the bar, the page's title centered; nothing else a web app needs.
private struct WebAppBar: View {
    let state: BrowserState
    weak var commands: BrowserCommands?
    static let height: CGFloat = 38

    var body: some View {
        let colors = state.palette
        let tab = state.activeTab
        ZStack {
            HStack(spacing: 2) {
                ChromeButton(symbol: "chevron.left", help: "Back", colors: colors, size: 26, enabled: tab?.canGoBack == true, glass: false) { commands?.goBack() }
                ChromeButton(symbol: "chevron.right", help: "Forward", colors: colors, size: 26, enabled: tab?.canGoForward == true, glass: false) { commands?.goForward() }
                ChromeButton(symbol: tab?.isLoading == true ? "xmark" : "arrow.clockwise", help: tab?.isLoading == true ? "Stop" : "Reload",
                             colors: colors, size: 26, glass: false) { commands?.reloadOrStop() }
                Spacer()
            }
            .padding(.leading, 86)
            Text(title(tab)).font(.system(size: 12, weight: .semibold)).foregroundStyle(colors.secondary).lineLimit(1)
                .padding(.horizontal, 190).allowsHitTesting(false)
        }
        .frame(height: Self.height)
        .background(WindowDragArea())
    }

    private func title(_ tab: TabItem?) -> String {
        let page = tab?.title ?? ""
        return page.isEmpty ? state.webApp?.name ?? "" : page
    }
}
