import SwiftUI

/// Tab groups: one switch for their look (the Sidebar layout), and where they show (Top Tabs).
struct GroupAppearanceSection: View {
    let state: BrowserState

    var body: some View {
        PageSection(title: "Tab Groups", footer: "Right-click a group to change its color or hide it.") {
            if state.usesTabsLayout {
                PageRow(title: "Where groups show", subtitle: "Chips in the tab row, or tiles in the icon sidebar",
                        figure: AnyView(GroupPlacementFigure(placement: state.groupPlacement, colors: state.palette))) {
                    SettingsSegmented(selection: Binding(
                        get: { state.groupPlacement },
                        set: { placement in withAnimation(.ikago) { state.browserPreferences.groupPlacement = placement == .topBar ? nil : placement } }),
                        options: GroupPlacement.allCases.map { ($0, $0.name) })
                }
            } else {
                PageRow(title: "Color pill", subtitle: "Colored names in tinted cards. Off, a small color marker in a folder list",
                        figure: AnyView(GroupStyleFigure(pills: state.groupsAsPills, colors: state.palette))) {
                    Toggle("Color pill", isOn: Binding(
                        get: { state.groupsAsPills },
                        set: { on in withAnimation(.ikago) { state.groupLabelStyle = on ? .colorPill : .minimal } }))
                        .labelsHidden().toggleStyle(.switch)
                }
            }
        }
    }
}
