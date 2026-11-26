import SwiftUI

/// One customizable control (Settings ▸ Customize), as it appears in the sidebar.
struct ChromeItemView: View {
    let item: ChromeItem
    let state: BrowserState
    let colors: Palette
    weak var commands: BrowserCommands?
    var size: CGFloat = 28
    /// In the sidebar's bottom bar "Spaces" is the row of dots; elsewhere it is a menu.
    var spacesAsDots = false
    /// Drawn in the full sidebar that Expand opens over the icon rail: the sidebar button keeps it open.
    @Environment(\.sidebarOverRail) private var overRail

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
        case .sidebarToggle:
            if overRail { button(help: "Keep the Sidebar Open") { commands?.showFullSidebar() } }
            else { button(help: "Sidebar: Full, Icons, Hidden") { commands?.cycleSidebar() } }
        case .newTab: button(help: "New Tab (⌘T)") { commands?.newTab() }
        case .newSpace: button(help: "New Space (⇧⌘N)") { commands?.newSpace() }
        case .bookmarks: button(help: "Bookmarks (⌥⌘B)") { commands?.openPage(.bookmarks) }
        case .history: button(help: "History (⌘Y)") { commands?.openPage(.history) }
        case .downloads: DownloadToolbarButton(colors: colors, commands: commands, size: size)
        case .devices: DevicesToolbarButton(colors: colors, commands: commands, size: size)
        case .siteInfo:
            button(help: "Site Settings and Extensions") { (commands as? BrowserWindowController)?.toggleSiteInfo(fromToolbar: true) }
        case .settings: button(help: "Settings (⌘,)") { commands?.openPage(.settings) }
        case .tabGroups: TabGroupsButton(state: state, colors: colors, size: size)
        case .assistant:
            if state.browserPreferences.pageIntelligence == true { button(help: "Ask this page") { commands?.togglePageAssistant() } }
        case .notes: button(help: "Notes") { commands?.openPage(.notes) }
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

/// Controls that didn't fit in the sidebar's top row, as a menu. Only plain buttons land here (`anchorsPopover`).
struct ChromeOverflowMenu: View {
    let items: [ChromeItem]
    let state: BrowserState
    let colors: Palette
    weak var commands: BrowserCommands?
    var size: CGFloat = 28

    var body: some View {
        Menu {
            ForEach(items) { item in
                Button { perform(item) } label: { Label(item.name, systemImage: item.symbol) }
                    .disabled(!enabled(item))
            }
        } label: {
            Image(systemName: "chevron.right.2")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(colors.glass ? colors.text.opacity(0.85) : colors.secondary)
                .frame(width: size, height: size)
                .contentShape(Circle()).glassControl(Circle(), colors)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More")
    }

    private func enabled(_ item: ChromeItem) -> Bool {
        switch item {
        case .back: state.activeTab?.canGoBack == true
        case .forward: state.activeTab?.canGoForward == true
        case .reload: state.activeTab != nil
        default: true
        }
    }

    private func perform(_ item: ChromeItem) {
        switch item {
        case .back: commands?.goBack()
        case .forward: commands?.goForward()
        case .reload: commands?.reloadOrStop()
        case .sidebarToggle: commands?.cycleSidebar()
        case .newTab: commands?.newTab()
        case .newSpace: commands?.newSpace()
        case .bookmarks: commands?.openPage(.bookmarks)
        case .history: commands?.openPage(.history)
        case .settings: commands?.openPage(.settings)
        case .assistant: commands?.togglePageAssistant()
        case .notes: commands?.openPage(.notes)
        case .spaces, .downloads, .devices, .siteInfo, .share, .tabGroups: break
        }
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

private struct SidebarOverRailKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// Inside the full sidebar that the icon rail's Expand opens over the page (`RailExpandPanel`).
    var sidebarOverRail: Bool {
        get { self[SidebarOverRailKey.self] }
        set { self[SidebarOverRailKey.self] = newValue }
    }
}
