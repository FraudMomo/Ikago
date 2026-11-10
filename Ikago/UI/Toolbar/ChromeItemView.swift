import SwiftUI

/// One customizable control (Settings ▸ Customize), as it appears in the top bar or sidebar.
struct ChromeItemView: View {
    let item: ChromeItem
    let state: BrowserState
    let colors: Palette
    weak var commands: BrowserCommands?
    var size: CGFloat = 28
    /// In the sidebar's bottom bar "Spaces" is the row of dots; elsewhere it is a menu.
    var spacesAsDots = false

    var body: some View {
        let tab = state.activeTab
        switch item {
        case .spaces:
            if spacesAsDots { SpaceBar(state: state, colors: colors, commands: commands) }
            else { SpaceMenu(state: state, colors: colors, commands: commands) }
        case .back:
            button(enabled: tab?.canGoBack == true, help: "Back (⌘[)") { commands?.goBack() }
        case .forward:
            button(enabled: tab?.canGoForward == true, help: "Forward (⌘])") { commands?.goForward() }
        case .reload:
            ChromeButton(symbol: tab?.isLoading == true ? "stop.fill" : "arrow.clockwise", help: "Reload (⌘R)",
                         colors: colors, size: size, enabled: tab != nil) { commands?.reloadOrStop() }
        case .sidebarToggle: button(help: "Sidebar: Full, Icons, Hidden") { commands?.cycleSidebar() }
        case .newTab: button(help: "New Tab (⌘T)") { commands?.newTab() }.contextMenu { ClosedGroupItems(state: state) }
        case .newSpace: button(help: "New Space (⇧⌘N)") { commands?.newSpace() }
        case .bookmarks: button(help: "Bookmarks (⌥⌘B)") { commands?.openPage(.bookmarks) }
        case .history: button(help: "History (⌘Y)") { commands?.openPage(.history) }
        case .downloads: DownloadToolbarButton(colors: colors, commands: commands, size: size)
        case .settings: button(help: "Settings (⌘,)") { commands?.openPage(.settings) }
        case .tabOverview: button(help: "Tab Overview (⇧⌘S)") { commands?.toggleSidebar() }
        case .share:
            if let tab, AddressResolver.isWebURL(tab.url), let url = URL(string: tab.url) {
                ShareLink(item: url) {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 14))
                        .foregroundStyle(colors.glass ? colors.text.opacity(0.85) : colors.secondary).frame(width: size, height: size)
                        .contentShape(Circle()).glassControl(Circle(), colors)
                }.buttonStyle(.plain).help("Share This Page")
            } else { button(enabled: false, help: "Share This Page") {} }
        }
    }

    private func button(enabled: Bool = true, help: String, action: @escaping () -> Void) -> some View {
        ChromeButton(symbol: item.symbol, help: help, colors: colors, size: size, enabled: enabled, action: action)
    }
}

/// The active Space; click to switch Spaces or add one.
struct SpaceMenu: View {
    let state: BrowserState
    let colors: Palette
    weak var commands: BrowserCommands?

    var body: some View {
        Menu {
            ForEach(state.spaces) { space in
                Button { withAnimation(.ikago) { state.switchSpace(space.id) } } label: {
                    Label(space.name, systemImage: space.symbol)
                }
            }
            Divider()
            Button("New Space…") { commands?.newSpace() }
        } label: {
            Image(systemName: state.activeSpace.symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(colors.glass ? colors.text.opacity(0.85) : colors.secondary)
                .frame(width: 26, height: 26)
                .contentShape(Circle()).glassControl(Circle(), colors)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(state.activeSpace.name)
    }
}
