import SwiftUI

/// The controls placed inside the address field (Settings ▸ Customize ▸ In the address field), after the address, in
/// every layout. Reload and Site & Extensions stay quiet until the pointer is over the field (Reload also while a page
/// loads, Site & Extensions while a site asks for something); the others always show, as plain icons.
struct AddressFieldControls: View {
    let state: BrowserState
    let colors: Palette
    weak var commands: BrowserCommands?
    /// The pointer is over the address field.
    let hovering: Bool
    var size: CGFloat = 24

    var body: some View {
        let items = state.visibleChromeItems(state.chromeLayout.address)
        let tab = state.activeTab
        HStack(spacing: 0) {
            // A loading page can always be stopped, wherever Reload is placed.
            if let tab, tab.isLoading, !items.contains(.reload) { PageLoadButton(tab: tab, colors: colors, commands: commands) }
            ForEach(items) { item in
                switch item {
                case .reload:
                    if let tab, tab.isLoading || hovering { PageLoadButton(tab: tab, colors: colors, commands: commands) }
                case .siteInfo:
                    if hovering || SiteInfoButton.isShown(commands) {
                        SiteInfoButton(state: state, colors: colors, commands: commands)
                            .transition(.opacity.combined(with: .scale(scale: 0.7)))
                    }
                default:
                    ChromeItemView(item: item, state: state, colors: colors, commands: commands, size: size)
                }
            }
        }
        .environment(\.inGlassGroup, true)
    }
}
