import SwiftUI

/// Custom toolbar items remain reachable when a small window cannot fit them beside the tabs.
struct ChromeOverflowMenu: View {
    let items: [ChromeItem]
    let state: BrowserState
    let colors: Palette
    let size: CGFloat
    weak var commands: BrowserCommands?

    var body: some View {
        Menu {
            ForEach(items) { item in
                if item == .spaces {
                    Menu("Spaces") {
                        ForEach(state.spaces) { space in
                            Button { state.switchSpace(space.id) } label: { Label(space.name, systemImage: space.symbol) }
                        }
                        Button("New Space…") { commands?.newSpace() }
                    }
                } else if item == .share, let tab = state.activeTab, AddressResolver.isWebURL(tab.url), let url = URL(string: tab.url) {
                    ShareLink(item: url) { Label("Share This Page", systemImage: "square.and.arrow.up") }
                } else {
                    Button { perform(item) } label: { Label(item.name, systemImage: item.symbol) }
                        .disabled(item == .back && state.activeTab?.canGoBack != true || item == .forward && state.activeTab?.canGoForward != true)
                }
            }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 13, weight: .medium))
                .foregroundStyle(colors.glass ? colors.text.opacity(0.85) : colors.secondary).frame(width: size, height: size)
                .contentShape(Circle()).glassControl(Circle(), colors)
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .anchorPreference(key: DownloadsAnchorKey.self, value: .bounds) { DownloadAnchors(toolbar: items.contains(.downloads) ? $0 : nil) }
        .help("More Toolbar Controls").accessibilityLabel("More toolbar controls")
    }

    private func perform(_ item: ChromeItem) {
        switch item {
        case .sidebarToggle: commands?.cycleSidebar()
        case .back: commands?.goBack()
        case .forward: commands?.goForward()
        case .reload: commands?.reloadOrStop()
        case .newTab: commands?.newTab()
        case .newSpace: commands?.newSpace()
        case .bookmarks: commands?.openPage(.bookmarks)
        case .history: commands?.openPage(.history)
        case .downloads: commands?.toggleDownloads()
        case .settings: commands?.showSettings()
        case .spaces: break
        case .tabOverview: commands?.toggleSidebar()
        case .share: break
        }
    }
}

struct IslandToolbarLayout {
    var leading: [ChromeItem]
    var trailing: [ChromeItem]
    var overflow: [ChromeItem] = []
    let available: CGFloat
    let floating: Bool
    let size: CGFloat

    init(leading: [ChromeItem], trailing: [ChromeItem], available: CGFloat, floating: Bool, size: CGFloat) {
        self.leading = leading; self.trailing = trailing; self.available = available; self.floating = floating; self.size = size
        let minimum = min(80, max(0, available - (floating ? 80 : 0) - 6))
        while viewport < minimum && (!self.leading.isEmpty || !self.trailing.isEmpty) {
            if let item = self.trailing.popLast() { overflow.insert(item, at: 0) }
            else if let item = self.leading.popLast() { overflow.insert(item, at: 0) }
        }
    }
    var viewport: CGFloat {
        let controls = leading + trailing
        let buttons = controls.reduce(CGFloat.zero) { $0 + ($1 == .spaces ? 26 : size) } + (overflow.isEmpty ? 0 : size)
        let children = controls.count + (overflow.isEmpty ? 0 : 1) + 1 + (floating ? 3 : 0)
        return max(0, available - buttons - CGFloat(max(0, children - 1)) * 2 - 6 - (floating ? 80 : 0))
    }
}
