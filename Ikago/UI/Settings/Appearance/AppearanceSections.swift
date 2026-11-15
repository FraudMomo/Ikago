import SwiftUI

/// Settings ▸ Appearance: mode, colors and glass.
struct AppearanceSection: View {
    let state: BrowserState

    var body: some View {
        PageSection(title: "Color & Theme") {
            PageRow(title: "Appearance") {
                AppearanceModePicker(state: state).padding(.vertical, 5)
            }
            PageDivider()
            SpaceThemePicker(state: state)
            PageDivider()
            SpaceColorEditor(state: state)
        }
        PageSection(title: "Materials") {
            PageRow(title: "Liquid Glass", subtitle: "Glass on toolbars and overlays") {
                Toggle("", isOn: Binding(get: { state.useGlass }, set: { on in withAnimation(.ikago) { state.useGlass = on } }))
                    .labelsHidden().toggleStyle(.switch)
            }
            PageDivider()
            PageRow(title: "Translucent sidebar", subtitle: "Frosted material tinted with your Space color") {
                Toggle("Translucent sidebar", isOn: Binding(
                    get: { state.browserPreferences.translucentSidebar ?? false },
                    set: { state.browserPreferences.translucentSidebar = $0 }))
                    .labelsHidden().toggleStyle(.switch)
            }
        }
    }
}

struct TabMotionSection: View {
    let state: BrowserState

    var body: some View {
        PageSection(title: "Tab Animations") {
            PageRow(title: "Instant tab switching", subtitle: "No fade between pages") {
                Toggle("Instant tab switching", isOn: Binding(
                    get: { state.browserPreferences.instantTabSwitching ?? false },
                    set: { state.browserPreferences.instantTabSwitching = $0 }))
                    .labelsHidden().toggleStyle(.switch)
            }
            PageDivider()
            PageRow(title: "Tab highlight animation") {
                SettingsMenu(selection: Binding(get: { state.tabHighlightStyle }, set: { state.tabHighlightStyle = $0 }), options: TabHighlightStyle.allCases.map { ($0, $0.title) })
            }
        }
    }
}

/// Layout-specific dimensions; Chrome keeps its reference proportions.
struct SpacingSection: View {
    @Bindable var state: BrowserState

    var body: some View {
        PageSection(title: "Window and Sidebar") {
            SliderRow(title: "Window border", subtitle: "Space around the page", value: $state.frameInset,
                      range: 0...24, defaultValue: BrowserState.defaultFrameInset)
            PageDivider()
            Group {
                PageRow(title: "Sidebar", subtitle: "⌃⌘S switches, ⇧⌘S hides") {
                    SettingsSegmented(selection: Binding(
                        get: { !state.sidebarVisible ? 2 : state.showsSidebarRail ? 1 : 0 },
                        set: { mode in
                            withAnimation(.ikago) {
                                state.sidebarVisible = mode != 2
                                if mode != 2 { state.browserPreferences.sidebarCompact = mode == 1 ? true : nil }
                            }
                        }),
                        // Sidebar + Tabs has no full sidebar.
                        options: (state.usesTabsLayout ? [] : [(0, "Full")]) + [(1, "Icons"), (2, "Hidden")])
                }
                PageDivider()
                PageRow(title: "Sidebar side") {
                    SettingsSegmented(selection: Binding(get: { state.sidebarOnRight }, set: { state.sidebarOnRight = $0 }), options: [(false, "Left"), (true, "Right")])
                }
                if state.sidebarOnRight {
                    PageDivider()
                    PageRow(title: "Move window controls with sidebar") {
                        Toggle("Move window controls with sidebar", isOn: Binding(get: { state.sidebarLightsFollow }, set: { state.sidebarLightsFollow = $0 })).labelsHidden().toggleStyle(.switch)
                    }
                }
                PageDivider()
                SliderRow(title: "Sidebar gap", subtitle: "Space between the sidebar and page",
                          value: $state.sidebarGap, range: 0...24, defaultValue: BrowserState.defaultSidebarGap)
            }
        }
        PageSection(title: "Full Screen") {
            PageRow(title: "Use the area beside the camera", subtitle: "Otherwise a black band sits below it") {
                Toggle("Use the area beside the camera", isOn: Binding(
                    get: { state.browserPreferences.fullScreenUnderNotch == true },
                    set: { state.browserPreferences.fullScreenUnderNotch = $0 ? true : nil }))
                    .labelsHidden().toggleStyle(.switch)
            }
        }
    }
}
