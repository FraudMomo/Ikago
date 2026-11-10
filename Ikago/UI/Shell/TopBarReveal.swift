import SwiftUI

/// Full screen with top bars: the page has the whole screen, and touching the top edge drops the bars in
/// over it as one floating sheet. It leaves
/// shortly after the pointer does, unless something in it is in use (`ChromeModel.holdsPeek`).
struct TopBarReveal: View {
    let state: BrowserState
    let chrome: ChromeModel
    let palette: CommandPaletteModel
    weak var commands: BrowserCommands?

    var body: some View {
        ZStack(alignment: .top) {
            // A thin strip along the top edge; the band above it belongs to the menu bar.
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 6)
                .contentShape(Rectangle())
                .onHover { if $0 { chrome.peek() } }
            if chrome.peeking {
                IsolatedHost(chrome: chrome) {
                    TopBarBrowserView(state: state, chrome: chrome, palette: palette, commands: commands)
                }
                    .frame(height: state.topBarHeaderHeight)
                    .background {
                        // A floating header casts its own shadow; a docked one gets it from its outline here.
                        if !state.barFloating {
                            CardShadow(shape: Rectangle(), color: .black.opacity(state.isDark ? 0.42 : 0.16), radius: 18, y: 6)
                        }
                    }
                    .padding(.top, state.immersiveChromeTop)
                    .onHover { inside in
                        chrome.peekHovered = inside
                        if inside { chrome.peek() } else { chrome.endPeek() }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .recordLayout("topbar-reveal")
    }
}
