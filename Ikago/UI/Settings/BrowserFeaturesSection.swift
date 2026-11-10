import SwiftUI

struct BrowserFeaturesSection: View {
    @Bindable var state: BrowserState

    var body: some View {
        PageSection(title: "Background Tabs") {
            PageRow(title: "Load new tabs in the background") {
                Toggle("Load new tabs in the background", isOn: Binding(get: { state.browserPreferences.loadBackgroundTabs ?? true },
                    set: { state.browserPreferences.loadBackgroundTabs = $0 })).labelsHidden().toggleStyle(.switch)
            }
        }
        PageSection(title: "Memory", footer: "Sleeping tabs reload when selected. Visible, playing and loading tabs stay awake.") {
            PageRow(title: "Hibernate inactive tabs", subtitle: "Free memory from background tabs") {
                Toggle("Hibernate inactive tabs", isOn: $state.browserPreferences.hibernationEnabled)
                    .labelsHidden().toggleStyle(.switch)
            }
            if state.browserPreferences.hibernationEnabled {
                PageDivider()
                PageRow(title: "Hibernate after") {
                    Picker("Idle time", selection: $state.browserPreferences.hibernationMinutes) {
                        ForEach(Array(Set([5, 15, 30, 60, 120, state.browserPreferences.hibernationMinutes])).sorted(), id: \.self) {
                            Text($0 == 1 ? "1 minute" : "\($0) minutes").tag($0)
                        }
                    }.labelsHidden()
                }
                PageDivider()
                PageRow(title: "Keep pinned tabs awake") {
                    Toggle("Keep pinned tabs awake", isOn: $state.browserPreferences.protectPinnedTabs)
                        .labelsHidden().toggleStyle(.switch)
                }
                PageDivider()
                PageRow(title: "Always keep these sites awake", subtitle: "Comma-separated, includes subdomains") {
                    TextField("mail.example.com, example.org", text: $state.browserPreferences.hibernationExceptions)
                        .textFieldStyle(.roundedBorder).frame(maxWidth: 280)
                }
            }
        }
    }
}

struct TabPlacementSection: View {
    @Bindable var state: BrowserState

    var body: some View {
        PageSection(title: "Tab Placement", footer: "Applies to the Sidebar layout.") {
            PageRow(title: "New tab position") {
                Picker("New tab position", selection: $state.newTabPosition) {
                    ForEach(NewTabPosition.allCases) { Text($0.title).tag($0) }
                }.labelsHidden()
            }
            PageDivider()
            PageRow(title: "Links opened in new tabs") {
                Picker("Links opened in new tabs", selection: $state.linkTabPosition) {
                    ForEach(LinkTabPosition.allCases) { Text($0.title).tag($0) }
                }.labelsHidden()
            }
        }
    }
}
