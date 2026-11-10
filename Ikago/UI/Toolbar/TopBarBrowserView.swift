import SwiftUI

/// The Top Bar layout has one native-looking surface: toolbar above Separate tabs, or Compact tabs in it.
struct TopBarBrowserView: View {
    let state: BrowserState
    let chrome: ChromeModel
    let palette: CommandPaletteModel
    weak var commands: BrowserCommands?

    var body: some View {
        let colors = state.topBarPalette
        VStack(spacing: 0) {
            if state.topTabStyle == .separate {
                TopToolbar(state: state, chrome: chrome, palette: palette, commands: commands)
                if state.topBarShowsTabStrip {
                    TopTabStrip(state: state, chrome: chrome, commands: commands)
                        .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)), removal: .identity))
                }
            } else if chrome.isEditingAddress(of: state.activeTabID),
                      state.activeTab.map({ $0.pinned || state.splitGroup(of: $0.id) != nil
                          || state.folders.contains(where: { $0.id == state.activeTab?.folderID && !$0.isOpen }) }) == true {
                TopToolbar(state: state, chrome: chrome, palette: palette, commands: commands)
            } else {
                IslandBarView(state: state, chrome: chrome, palette: palette, commands: commands,
                              foldOutsideControls: true, reserveTrafficLights: true)
                    .recordLayout("connected-tab-row")
            }
            if state.showsBookmarksBar { BookmarksBar(state: state, chrome: chrome, commands: commands) }
        }
        // Only the Separate tab bar's reveal animates; everything else in the header stays immediate.
        .animation(.ikago, value: state.topBarShowsTabStrip)
        .clipShape(.rect(cornerRadius: state.barFloating ? Self.floatingRadius : 0, style: .continuous))
        .surface(.rect(cornerRadius: state.barFloating ? Self.floatingRadius : 0, style: .continuous), colors, tintOpacity: state.barFloating ? 0.15 : 0.65)
        .overlay {
            if state.barFloating && state.barBorder > 0 {
                RoundedRectangle(cornerRadius: Self.floatingRadius, style: .continuous)
                    .strokeBorder(colors.text.opacity(0.22), lineWidth: state.barBorder)
            }
        }
        // Docked, the toolbar meets the page on a hairline; floating, it is a detached card with its own shadow.
        .overlay(alignment: .bottom) {
            if !state.barFloating { Rectangle().fill(colors.separator).frame(height: 0.5).allowsHitTesting(false) }
        }
        // Floating, the card casts its shadow from its outline (`CardShadow`): a `.shadow` here would re-render
        // the whole header on every progress tick and hover. Docked, there is none.
        .background {
            if state.barFloating {
                let card = RoundedRectangle(cornerRadius: Self.floatingRadius, style: .continuous)
                CardShadow(shape: card, color: .black.opacity(colors.isDark ? 0.45 : 0.16), radius: 12, y: 4)
                CardShadow(shape: card, color: .black.opacity(0.08), radius: 1, y: 0.5)
            }
        }
        .padding(state.barFloating ? BrowserState.topBarFloatingMargin : 0)
        // Floating, the margin above and beside the card moves the window too (not the band below it,
        // which is page).
        .background(alignment: .top) {
            if state.barFloating {
                WindowDragArea().frame(height: max(0, state.topBarHeaderHeight - BrowserState.topBarFloatingMargin))
            }
        }
        .frame(height: state.topBarHeaderHeight)
        .environment(\.colorScheme, colors.isDark ? .dark : .light)
        .environment(\.tabHighlightStyle, .none)
        .recordLayout("top-header")
        .recordLayout("connected-topbar")
        .transaction { $0.animation = nil }
    }

    static let floatingRadius: CGFloat = 14
}
