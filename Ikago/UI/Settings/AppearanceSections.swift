import SwiftUI

/// Settings ▸ Appearance: mode, colors and glass.
struct AppearanceSection: View {
    let state: BrowserState

    var body: some View {
        PageSection(title: "Color & Theme", footer: "Each Space has its own color, one for light mode and one for dark mode.") {
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
            PageRow(title: "Liquid Glass", subtitle: "Glass effects for browser chrome and overlays.") {
                Toggle("", isOn: Binding(get: { state.useGlass }, set: { on in withAnimation(.ikago) { state.useGlass = on } }))
                    .labelsHidden().toggleStyle(.switch)
            }
            PageDivider()
            PageRow(title: "Translucent sidebar", subtitle: "Frosted macOS material, like Xcode. Replaces Liquid Glass for sidebars and retains your Space color.") {
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
        PageSection(title: "Tab Animations", footer: "Page switching and the selected-tab highlight are independent. Applies to both layouts. Reduce Motion disables these animations.") {
            PageRow(title: "Instant tab switching", subtitle: "Show pages immediately, without the fade transition") {
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
                PageRow(title: "Sidebar", subtitle: "Full shows titles; Icons is a slim rail. ⌃⌘S switches, ⇧⌘S hides it.") {
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
                PageRow(title: "Floating toolbar", subtitle: "Detach the toolbar from the window edges as a shadowed card over the page.") {
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
            PageRow(title: "Use the area beside the camera", subtitle: "Fill the whole display, so the page runs up beside the camera housing. Off, a black band keeps it below.") {
                Toggle("Use the area beside the camera", isOn: Binding(
                    get: { state.browserPreferences.fullScreenUnderNotch == true },
                    set: { state.browserPreferences.fullScreenUnderNotch = $0 ? true : nil }))
                    .labelsHidden().toggleStyle(.switch)
            }
        }
    }
}
