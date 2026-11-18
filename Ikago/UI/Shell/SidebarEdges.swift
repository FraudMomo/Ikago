import SwiftUI

extension View {
    /// The sidebar's card (docked or revealed): glass, or a flat panel. A revealed card casts its shadow from its
    /// outline (`CardShadow`), never with `.shadow`, which would re-render every tab title on each scroll frame.
    func sidebarPanel(_ colors: Palette, radius: CGFloat, shadow: Double = 0, translucent: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius == 0 ? 0 : radius + 4)
        return surface(shape, colors, translucentSidebar: translucent)
            .background { if shadow > 0 { CardShadow(shape: shape, color: .black.opacity(shadow), radius: 16, x: 2, y: 3) } }
    }
}


/// The gap between sidebar and page: drag to resize the sidebar, double-click to reset it.
struct SidebarResizeHandle: View {
    let state: BrowserState
    let width: CGFloat
    @State private var startWidth: Double?
    @State private var hovering = false
    private let grab: CGFloat = 10  // hit area, even when the gap is 0

    var body: some View {
        Color.clear
            .frame(width: width)
            .overlay {
                Color.clear
                    .frame(width: max(width, grab))
                    .contentShape(Rectangle())
                    .overlay {  // a faint line while hovering or dragging
                        Capsule().fill(state.palette.tertiary).frame(width: 2, height: 36)
                            .opacity(hovering || startWidth != nil ? 1 : 0)
                    }
                    .pointerStyle(.columnResize)
                    .onHover { hovering = $0 }
                    .onTapGesture(count: 2) { withAnimation(.ikago) { state.sidebarWidth = BrowserState.defaultSidebarWidth } }
                    .gesture(drag)
                    .help("Drag to resize the sidebar · double-click to reset")
            }
            .zIndex(1)
            .animation(.ikagoQuick, value: hovering)
    }

    /// Measured in window coordinates: the handle moves with the sidebar, so local
    /// coordinates would feed each step back into the next (the jitter).
    private var drag: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                let start = startWidth ?? state.sidebarWidth
                startWidth = start
                var instant = Transaction()
                instant.disablesAnimations = true
                withTransaction(instant) {
                    state.sidebarWidth = min(420, max(200, (start + value.translation.width * (state.sidebarOnRight ? -1 : 1)).rounded()))
                }
            }
            .onEnded { _ in startWidth = nil }
    }
}

/// Collapsed sidebar: touching the left edge slides it in as a floating glass panel.
struct SidebarPeek: View {
    let state: BrowserState
    let chrome: ChromeModel
    let palette: CommandPaletteModel
    weak var commands: BrowserCommands?

    var body: some View {
        ZStack(alignment: state.sidebarOnRight ? .topTrailing : .topLeading) {
            // Hovering the edge brings the sidebar in (unless that's turned off; full screen always does, since its
            // window controls come with it); pressing it moves the window, like the margin it sits on.
            WindowDragArea()
                .frame(width: 10)
                .frame(maxHeight: .infinity)
                .onHover { if $0 && (state.sidebarEdgePeek || state.isImmersive) { chrome.peek() } }
            if chrome.peeking {
                IsolatedHost(chrome: chrome) {
                    // Top Tabs has no full sidebar: its rail slides in instead, under the tab row.
                    if state.usesTabsLayout { SidebarRail(state: state, commands: commands) }
                    else { SidebarView(state: state, chrome: chrome, palette: palette, commands: commands) }
                }
                    .frame(width: state.usesTabsLayout ? BrowserState.sidebarRailWidth : state.sidebarWidth)
                    .frame(maxHeight: .infinity)
                    .sidebarPanel(state.palette, radius: Radius.card, shadow: 0.18, translucent: state.browserPreferences.translucentSidebar == true)
                    .padding(max(state.frameInset, 6))
                    .padding(.top, state.isImmersive ? state.immersiveChromeTop : 0)
                    .padding(.top, state.showsSidebarTopTabs ? SidebarTopTabs.height(state) : 0)
                    .onHover { inside in
                        chrome.peekHovered = inside
                        if inside { chrome.peek() } else { chrome.endPeek() }
                    }
                    .transition(.move(edge: state.sidebarOnRight ? .trailing : .leading).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: state.sidebarOnRight ? .trailing : .leading)
    }
}
