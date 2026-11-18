import AppKit
import SwiftUI

/// Top Tabs in split view: each pane's own bar along its top, in place of the one address bar above the page. Back,
/// forward and reload act on this pane's page; its "site / title" opens the command bar for it; the close button closes
/// its tab. The pane in focus reads at full strength, the other a little quieter. Clicking the bar focuses its pane.
struct PaneBar: View {
    let tab: TabItem
    let state: BrowserState
    let perform: (PaneBarAction) -> Void

    var body: some View {
        let colors = state.palette
        let focused = tab.id == state.activeTabID
        HStack(spacing: 2) {
            ChromeButton(symbol: "chevron.left", help: "Back", colors: colors, size: 26, iconSize: 12,
                         enabled: tab.canGoBack, glass: false) { perform(.back) }
            ChromeButton(symbol: "chevron.right", help: "Forward", colors: colors, size: 26, iconSize: 12,
                         enabled: tab.canGoForward, glass: false) { perform(.forward) }
            ChromeButton(symbol: tab.isLoading ? "xmark" : "arrow.clockwise", help: tab.isLoading ? "Stop" : "Reload",
                         colors: colors, size: 26, iconSize: 12, glass: false) { perform(.reload) }
            Button { perform(.address) } label: {
                label(colors)
                    .font(.system(size: 12.5))
                    .padding(.leading, 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Search or enter address")
            ChromeButton(symbol: "xmark", help: "Close Tab", colors: colors, size: 24, iconSize: 10.5, glass: false) { perform(.close) }
        }
        .padding(.horizontal, 8)
        .opacity(focused ? 1 : 0.62)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Rectangle().fill(state.tabSheetColor).onTapGesture { perform(.focus) })
        .environment(\.colorScheme, colors.isDark ? .dark : .light)
        .animation(.ikagoQuick, value: focused)
    }

    /// The site strong, then the page's title quieter, fading out where it doesn't fit; a built-in page by its title.
    @ViewBuilder private func label(_ colors: Palette) -> some View {
        if AddressResolver.isWebURL(tab.url) {
            HStack(spacing: 5) {
                Text(tab.addressLabel).foregroundStyle(colors.text.opacity(0.92)).lineLimit(1).fixedSize().layoutPriority(1)
                if tab.displayTitle != tab.addressLabel {
                    Text("/").foregroundStyle(colors.tertiary).fixedSize()
                    Text(tab.displayTitle).foregroundStyle(colors.secondary).fadeTruncated()
                }
            }
        } else {
            Text(tab.displayTitle).foregroundStyle(colors.text.opacity(0.88)).fadeTruncated()
        }
    }
}

enum PaneBarAction { case back, forward, reload, address, close, focus }

extension TabController {
    /// Shows or removes this pane's bar (`PaneBar`); the page fills the rest of the pane (`TabHostView.pageFrame`).
    func showPaneBar(_ shown: Bool) {
        guard let state else { return }
        if !shown {
            guard paneBar != nil else { return }
            paneBar?.removeFromSuperview()
            paneBar = nil
            hostView.barHeight = 0
            return
        }
        if paneBar == nil {
            let bar = NSHostingView(rootView: PaneBar(tab: tab, state: state) { [weak self] in self?.perform($0) })
            bar.sizingOptions = []
            // The pane can reach under the title bar; the bar fills its own frame, not the part below the safe area.
            bar.safeAreaRegions = []
            bar.autoresizingMask = [.width, .minYMargin]
            paneBar = bar
        }
        guard let bar = paneBar else { return }
        if bar.superview !== hostView { hostView.addSubview(bar, positioned: .above, relativeTo: nil) }
        hostView.bar = bar
        hostView.barHeight = state.tabsToolbarHeight
    }

    private func perform(_ action: PaneBarAction) {
        let commands = host as? BrowserCommands
        switch action {
        case .back: page?.goBack()
        case .forward: page?.goForward()
        case .reload: if tab.isLoading { page?.stopLoading() } else { page?.reload() }
        case .address:
            state?.select(tab.id)
            commands?.showCommandPalette(newTab: false)
        case .close: commands?.closeTab(tab.id)
        case .focus: state?.select(tab.id)
        }
    }
}
