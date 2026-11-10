import SwiftUI

struct TopBarSettingsSection: View {
    @Bindable var state: BrowserState

    var body: some View {
        PageSection(title: "Top Bar Tabs", footer: "Compact puts tabs in the toolbar.") {
            PageRow(title: "Tab bar style") {
                Picker("Tab bar style", selection: $state.topTabStyle.animation(.ikago)) {
                    ForEach(TopTabStyle.allCases) { Text($0.name).tag($0) }
                }.labelsHidden().pickerStyle(.segmented).fixedSize()
            }
            if state.topTabStyle == .separate {
                PageDivider()
                PageRow(title: "Always show tab bar", subtitle: "Otherwise shown with two or more tabs") {
                    Toggle("Always show tab bar", isOn: $state.topBarAlwaysShowsTabBar.animation(.ikago)).labelsHidden().toggleStyle(.switch)
                }
            }
            PageDivider()
            SliderRow(title: state.topTabStyle == .compact ? "Tab bar height" : "Toolbar height",
                      subtitle: state.topTabStyle == .compact ? "The single row holding tabs and controls" : nil,
                      value: Binding(get: { Double(state.topToolbarHeight) }, set: { state.browserPreferences.topToolbarHeight = $0 }),
                      range: BrowserState.topToolbarHeights, defaultValue: BrowserState.defaultTopToolbarHeight)
            if state.topTabStyle == .separate {
                PageDivider()
                SliderRow(title: "Tab bar height", value: Binding(get: { Double(state.topTabBarHeight) },
                                                                  set: { state.browserPreferences.topTabBarHeight = $0 }),
                          range: BrowserState.topTabBarHeights, defaultValue: BrowserState.defaultTopTabBarHeight)
            }
            PageDivider()
            PageRow(title: "Show webpage color", subtitle: "A subtle tint from the page") {
                Toggle("Show webpage color", isOn: $state.topBarShowsPageColor.animation(.ikago)).labelsHidden().toggleStyle(.switch)
            }
        }
    }
}
