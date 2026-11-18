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
            PageRow(title: "Instant tab switching", subtitle: "No fade between pages",
                    figure: AnyView(PageSwitchFigure(instant: state.browserPreferences.instantTabSwitching ?? false, colors: state.palette))) {
                Toggle("Instant tab switching", isOn: Binding(
                    get: { state.browserPreferences.instantTabSwitching ?? false },
                    set: { state.browserPreferences.instantTabSwitching = $0 }))
                    .labelsHidden().toggleStyle(.switch)
            }
            PageDivider()
            PageRow(title: "Tab highlight animation", subtitle: "How the selection moves between tabs",
                    figure: AnyView(TabHighlightFigure(style: state.tabHighlightStyle, colors: state.palette))) {
                SettingsMenu(selection: Binding(get: { state.tabHighlightStyle }, set: { state.tabHighlightStyle = $0 }), options: TabHighlightStyle.allCases.map { ($0, $0.title) })
            }
        }
    }
}

/// Settings only the Top Tabs layout uses: how the address bar sits. Not shown in the Sidebar layout.
struct TabsLayoutSection: View {
    let state: BrowserState

    var body: some View {
        if state.usesTabsLayout {
        PageSection(title: "Top Tabs") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Address bar").font(.system(size: 13, weight: .medium))
                HStack(spacing: 14) {
                    ForEach(TabsAddressStyle.allCases) { style in
                        TabsAddressCard(style: style, selected: state.tabsAddressStyle == style, colors: state.palette) {
                            withAnimation(.ikago) { state.browserPreferences.tabsAddressStyle = style == .centered ? nil : style }
                        }
                    }
                }
                Text(state.tabsAddressStyle.summary).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .padding(.vertical, 14)
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
                      range: 0...24, defaultValue: BrowserState.defaultFrameInset,
                      figure: AnyView(WindowSpacingFigure(inset: state.frameInset, gap: state.sidebarGap, onRight: state.sidebarOnRight, colors: state.palette)))
            PageDivider()
            Group {
                PageRow(title: "Sidebar", subtitle: "⌃⌘S switches, ⇧⌘S hides",
                        figure: AnyView(SidebarModeFigure(mode: !state.sidebarVisible ? 2 : state.showsSidebarRail ? 1 : 0,
                                                          onRight: state.sidebarOnRight, colors: state.palette))) {
                    SettingsSegmented(selection: Binding(
                        get: { !state.sidebarVisible ? 2 : state.showsSidebarRail ? 1 : 0 },
                        set: { mode in
                            withAnimation(.ikago) {
                                state.sidebarVisible = mode != 2
                                if mode != 2 { state.browserPreferences.sidebarCompact = mode == 1 ? true : nil }
                            }
                        }),
                        // Top Tabs has no full sidebar.
                        options: (state.usesTabsLayout ? [] : [(0, "Full")]) + [(1, "Icons"), (2, "Hidden")])
                }
                PageDivider()
                PageRow(title: "Reveal at the window edge", subtitle: "A hidden sidebar slides in at the window's edge",
                        figure: AnyView(EdgePeekFigure(on: state.sidebarEdgePeek, rail: state.usesTabsLayout, colors: state.palette))) {
                    Toggle("Reveal at the window edge", isOn: Binding(
                        get: { state.sidebarEdgePeek },
                        set: { on in withAnimation(.ikago) { state.browserPreferences.sidebarEdgePeek = on ? nil : false } }))
                        .labelsHidden().toggleStyle(.switch)
                }
                // Only where there is an icon sidebar: Top Tabs, or the Sidebar layout's Icons.
                if state.usesTabsLayout || state.browserPreferences.sidebarCompact == true {
                    PageDivider()
                    PageRow(title: "Icon sidebar on hover", subtitle: "Show the names near the pointer, like the Dock, or slide out the full sidebar",
                            figure: AnyView(RailHoverFigure(effect: state.browserPreferences.railHover, colors: state.palette))) {
                        SettingsMenu(selection: Binding(
                            get: { state.browserPreferences.railHover },
                            set: { state.browserPreferences.railHover = $0 }
                        ), options: [(nil, "Off")] + RailHoverEffect.allCases.map { (Optional($0), $0.name) })
                    }
                }
                PageDivider()
                PageRow(title: "Sidebar side", subtitle: "Left or right of the page",
                        figure: AnyView(WindowSpacingFigure(inset: state.frameInset, gap: state.sidebarGap, onRight: state.sidebarOnRight, colors: state.palette))) {
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
                          value: $state.sidebarGap, range: 0...24, defaultValue: BrowserState.defaultSidebarGap,
                          figure: AnyView(WindowSpacingFigure(inset: state.frameInset, gap: state.sidebarGap, onRight: state.sidebarOnRight, colors: state.palette)))
            }
        }
        PageGrabSection(state: state)
        PageSection(title: "Full Screen") {
            PageRow(title: "Use the area beside the camera", subtitle: "Otherwise a black band sits below it",
                    figure: AnyView(NotchFigure(besideCamera: state.browserPreferences.fullScreenUnderNotch == true, colors: state.palette))) {
                Toggle("Use the area beside the camera", isOn: Binding(
                    get: { state.browserPreferences.fullScreenUnderNotch == true },
                    set: { state.browserPreferences.fullScreenUnderNotch = $0 ? true : nil }))
                    .labelsHidden().toggleStyle(.switch)
            }
        }
    }
}
