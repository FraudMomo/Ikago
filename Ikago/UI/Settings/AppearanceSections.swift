import SwiftUI

/// Settings ▸ Appearance: mode, colors and glass.
struct AppearanceSection: View {
    let state: BrowserState

    var body: some View {
        PageSection(title: "Color & Theme") {
            PageRow(title: "Appearance") {
                Picker("", selection: Binding(get: { state.colorMode }, set: { mode in withAnimation(.ikago) { state.colorMode = mode } })) {
                    ForEach(ColorMode.allCases) { Text($0.name).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
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
                Picker("Tab highlight animation", selection: Binding(get: { state.tabHighlightStyle }, set: { state.tabHighlightStyle = $0 })) {
                    ForEach(TabHighlightStyle.allCases) { Text($0.title).tag($0) }
                }.labelsHidden()
            }
        }
    }
}

/// Layout-specific dimensions; Chrome keeps its reference proportions.
struct SpacingSection: View {
    @Bindable var state: BrowserState

    var body: some View {
        PageSection(title: state.tabLayout == .vertical ? "Window and Sidebar" : "Top Bar Window") {
            SliderRow(title: "Window border", subtitle: "Space around the page", value: $state.frameInset,
                      range: 0...24, defaultValue: BrowserState.defaultFrameInset)
            PageDivider()
            if state.tabLayout == .vertical {
                PageRow(title: "Sidebar", subtitle: "⌃⌘S switches, ⇧⌘S hides") {
                    Picker("Sidebar", selection: Binding(
                        get: { !state.sidebarVisible ? 2 : state.browserPreferences.sidebarCompact == true ? 1 : 0 },
                        set: { mode in
                            withAnimation(.ikago) {
                                state.sidebarVisible = mode != 2
                                if mode != 2 { state.browserPreferences.sidebarCompact = mode == 1 ? true : nil }
                            }
                        })) {
                        Text("Full").tag(0)
                        Text("Icons").tag(1)
                        Text("Hidden").tag(2)
                    }
                    .labelsHidden().pickerStyle(.segmented).fixedSize()
                }
                PageDivider()
                SliderRow(title: "Sidebar gap", subtitle: "Space between the sidebar and page",
                          value: $state.sidebarGap, range: 0...24, defaultValue: BrowserState.defaultSidebarGap)
            } else {
                PageRow(title: "Floating toolbar", subtitle: "A floating card over the page") {
                    Toggle("Floating toolbar", isOn: $state.barRounded.animation(.ikago)).labelsHidden().toggleStyle(.switch)
                }
                if state.barFloating {
                    PageDivider()
                    SliderRow(title: "Toolbar outline", value: $state.barBorder, range: 0...3, defaultValue: 0, step: 0.5,
                              format: { $0 == 0 ? "None" : String(format: "%.1f pt", $0) })
                }
            }
        }
        .animation(.ikago, value: state.tabLayout)
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
