import SwiftUI

/// Settings ▸ Appearance: moving the window from the page's top edge (`PageGrabMode`, `PageWindowGrab`), in every
/// layout, with or without a toolbar.
struct PageGrabSection: View {
    @Bindable var state: BrowserState

    var body: some View {
        let tabs = state.usesTabsLayout
        let mode = tabs ? .off : state.browserPreferences.pageGrab ?? .hold
        PageSection(title: "Moving the Window", footer: "Window margins and empty space in the sidebar and tab row always move the window.") {
            PageRow(title: "Move from the page's top edge",
                    subtitle: tabs ? "Sidebar + Tabs moves the window from its tab row" : mode.summary) {
                Toggle("Move from the page's top edge", isOn: Binding(
                    get: { mode != .off },
                    set: { on in withAnimation(.ikago) { state.browserPreferences.pageGrab = on ? nil : .off } }))
                    .labelsHidden().toggleStyle(.switch)
                    .disabled(tabs)
            }
            if mode != .off {
                PageDivider()
                PageRow(title: "Style") {
                    SettingsSegmented(selection: Binding(get: { mode }, set: { state.browserPreferences.pageGrab = $0 == .hold ? nil : $0 }),
                                      options: [PageGrabMode.hold, .header].map { ($0, $0.title) })
                }
                PageDivider()
                SliderRow(title: "Edge height", subtitle: "How far down from the top the edge reaches",
                          value: Binding(get: { state.browserPreferences.pageGrabHeight ?? PageGrabMode.defaultHeight },
                                         set: { state.browserPreferences.pageGrabHeight = $0 == PageGrabMode.defaultHeight ? nil : $0 }),
                          range: PageGrabMode.heights, defaultValue: PageGrabMode.defaultHeight)
                PageDivider()
                PageRow(title: "Double-click to zoom", subtitle: "Fills the screen, or returns to the earlier size") {
                    Toggle("Double-click to zoom", isOn: Binding(
                        get: { state.browserPreferences.pageGrabZoom ?? true },
                        set: { state.browserPreferences.pageGrabZoom = $0 ? nil : false }))
                        .labelsHidden().toggleStyle(.switch)
                }
            }
        }
        .animation(.ikago, value: mode)
    }
}

extension PageGrabMode {
    var summary: String {
        switch self {
        case .off: "The page keeps every click at its top"
        case .hold: "Press and hold at the top of the page, then drag"
        case .header: "Rest the pointer at the top and a small header drops down to drag"
        }
    }
}
